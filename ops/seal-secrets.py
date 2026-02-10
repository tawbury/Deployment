
import os
import sys
import subprocess
import json
import argparse
from pathlib import Path
from typing import Dict, List, Optional

# Configuration
PROJECT_ROOT = Path(__file__).resolve().parent.parent  # d:\development\deployment
REPO_ROOT = PROJECT_ROOT.parent # d:\development
PRJ_OBS_BASE = REPO_ROOT / "prj_obs"
PRJ_QTS_BASE = REPO_ROOT / "prj_qts"
SEALED_SECRETS_DIR = PROJECT_ROOT / "infra" / "k8s" / "base" / "sealed-secrets"
PUB_CERT_PATH = PROJECT_ROOT / "pub-cert.pem"

# Secret Mappings
# key_map: { "TargetSecretKey": "SourceEnvVarName" }
# If SourceEnvVarName is None, it looks for TargetSecretKey in env.
SECRET_MAPPINGS = {
    "obs-db-sealed-secret.yaml": {
        "source_dirs": [PRJ_OBS_BASE / "config"], # Order matters
        "secret_name": "obs-db-secret",
        "key_map": {
            "POSTGRES_USER": "DB_USER",
            "POSTGRES_PASSWORD": "DB_PASSWORD",
            "POSTGRES_DB": "DB_NAME",
            "DB_USER": "DB_USER",
            "DB_PASSWORD": "DB_PASSWORD"
        }
    },
    "obs-kis-sealed-secret.yaml": {
        "source_dirs": [PRJ_OBS_BASE / "config"],
        "secret_name": "obs-kis-secret",
        "key_map": {
            "KIS_APP_KEY": "KIS_APP_KEY",
            "KIS_APP_SECRET": "KIS_APP_SECRET",
            "KIS_HTS_ID": "KIS_HTS_ID"
        }
    },
    "obs-kiwoom-sealed-secret.yaml": {
        "source_dirs": [PRJ_OBS_BASE / "config"],
        "secret_name": "obs-kiwoom-secret",
        "key_map": {
            "KIWOOM_APP_KEY": "KIWOOM_APP_KEY",
            "KIWOOM_APP_SECRET": "KIWOOM_APP_SECRET",
            "KIWOOM_HTS_ID": "KIWOOM_HTS_ID"
        }
    },
    "qts-kis-sealed-secret.yaml": {
        "source_dirs": [PRJ_QTS_BASE / "config"],
        "secret_name": "qts-kis-secret",
        "key_map": {
            "KIS_VTS_APP_KEY": "KIS_VTS_APP_KEY",
            "KIS_VTS_APP_SECRET": "KIS_VTS_APP_SECRET",
            "KIS_VTS_ACCOUNT_NO": "KIS_VTS_ACCOUNT_NO",
            "KIS_REAL_APP_KEY": "KIS_REAL_APP_KEY",
            "KIS_REAL_APP_SECRET": "KIS_REAL_APP_SECRET",
            "KIS_REAL_ACCOUNT_NO": "KIS_REAL_ACCOUNT_NO"
        }
    },
    "qts-kiwoom-sealed-secret.yaml": {
         "source_dirs": [PRJ_QTS_BASE / "config"],
         "secret_name": "qts-kiwoom-secret",
         "key_map": {
            "KIWOOM_VTS_APP_KEY": "KIWOOM_VTS_APP_KEY",
            "KIWOOM_VTS_APP_SECRET": "KIWOOM_VTS_APP_SECRET",
            "KIWOOM_REAL_APP_KEY": "KIWOOM_REAL_APP_KEY",
            "KIWOOM_REAL_APP_SECRET": "KIWOOM_REAL_APP_SECRET"
         }
    },
    "qts-credentials-sealed-secret.yaml": {
        "source_dirs": [PRJ_QTS_BASE / "config"],
        "secret_name": "qts-credentials",
        "file_map": {
            "credentials.json": "credentials.json"
        }
    }
}

def load_env_file(filepath: Path) -> Dict[str, str]:
    """Parses a .env file into a dictionary."""
    env_vars = {}
    if not filepath.exists():
        return env_vars
    
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                
                # Handle "KEY=VALUE"
                if "=" in line:
                    key, value = line.split("=", 1)
                    key = key.strip()
                    value = value.strip()
                    
                    # Remove surrounding quotes 
                    if (value.startswith('"') and value.endswith('"')) or \
                       (value.startswith("'") and value.endswith("'")):
                        value = value[1:-1]
                    
                    env_vars[key] = value
    except Exception as e:
        print(f"Warning: Failed to read {filepath}: {e}")
        
    return env_vars

def get_merged_env_vars(source_dirs: List[Path]) -> Dict[str, str]:
    """Loads and merges .env files from list of config directories."""
    merged_env = {}
    
    for config_dir in source_dirs:
        # Define priority of files to load
        files_to_load = [
            config_dir / ".env.shared",  # Base shared vars
            config_dir / ".env",         # Secrets (Observer style)
            config_dir.parent / ".env",  # Secrets (QTS root style?) - checking parent of config
            config_dir / ".env.local"    # Local overrides
        ]
        
        for filepath in files_to_load:
            if filepath.exists():
                # print(f"  Loading: {filepath}")
                env_vars = load_env_file(filepath)
                merged_env.update(env_vars)
            
    return merged_env

def create_sealed_secret(filename, config, dry_run=False):
    """Generates a SealedSecret from env vars or files with mapping."""
    print(f"\nProcessing {filename}...")
    
    source_dirs = config["source_dirs"]
    key_map = config.get("key_map", {})
    file_map = config.get("file_map", {})
    secret_name = config["secret_name"]
    
    env_vars = get_merged_env_vars(source_dirs)
    
    # 1. Create temporary dry-run Secret
    cmd_create = [
        "kubectl", "create", "secret", "generic", secret_name,
        "--dry-run=client", "-o", "json"
    ]
    
    # Handle literals (key_map)
    missing_literals = []
    for target_key, source_key in key_map.items():
        if source_key in env_vars:
            cmd_create.extend(["--from-literal", f"{target_key}={env_vars[source_key]}"])
        else:
            missing_literals.append(f"{target_key}(from {source_key})")
            
    if missing_literals:
        print(f"  [Error] Missing environment variables for {filename}: {', '.join(missing_literals)}")
        return

    # Handle files (file_map)
    missing_files = []
    for target_key, source_filename in file_map.items():
        found = False
        for config_dir in source_dirs:
            file_path = config_dir / source_filename
            if file_path.exists():
                cmd_create.extend(["--from-file", f"{target_key}={file_path}"])
                found = True
                break
        if not found:
            missing_files.append(source_filename)
            
    if missing_files:
        print(f"  [Error] Missing files for {filename}: {', '.join(missing_files)}")
        return

    try:
        # Generate the secret JSON
        result = subprocess.run(cmd_create, capture_output=True, text=True, check=True)
        secret_json = json.loads(result.stdout)
        
        # 2. Remove namespace to allow cluster-wide usage / arbitrary namespace injection
        if "metadata" in secret_json:
            if "namespace" in secret_json["metadata"]:
                del secret_json["metadata"]["namespace"]
            # Also ensure creationTimestamp is removed
            if "creationTimestamp" in secret_json["metadata"]:
                del secret_json["metadata"]["creationTimestamp"]
            
        # 3. Seal the secret
        cmd_seal = [
            "kubeseal",
            "--cert", str(PUB_CERT_PATH),
            "--scope", "cluster-wide",
            "--format", "yaml"
        ]
        
        # Pass the modified secret JSON to kubeseal via stdin
        input_json_str = json.dumps(secret_json)
        
        seal_result = subprocess.run(
            cmd_seal,
            input=input_json_str,
            capture_output=True,
            text=True,
            check=True,
            encoding='utf-8'
        )
        
        output_path = SEALED_SECRETS_DIR / filename
        
        if dry_run:
             print(f"  [Dry-Run] Would write to {output_path}")
             # print(seal_result.stdout[:200] + "...")
        else:
            with open(output_path, "w", encoding="utf-8") as f:
                f.write(seal_result.stdout)
            print(f"  Successfully wrote to {output_path}")

    except subprocess.CalledProcessError as e:
        print(f"  [Subprocess Error] Command: {' '.join(e.cmd)}")
        print(f"  Stderr: {e.stderr}")
    except Exception as e:
        print(f"  [Exception] An error occurred: {e}")

def main():
    parser = argparse.ArgumentParser(description="Generate SealedSecrets from local .env files.")
    parser.add_argument("--target", choices=["all", "observer", "qts"], default="all", help="Target project secrets to update")
    parser.add_argument("--dry-run", action="store_true", help="Print actions without writing files")
    
    args = parser.parse_args()

    print(f"Checking for public certificate at: {PUB_CERT_PATH}")
    if not PUB_CERT_PATH.exists():
        print(f"[Error] Public certificate not found at {PUB_CERT_PATH}")
        print("Please ensure pub-cert.pem is present in the deployment root.")
        sys.exit(1)
        
    print(f"Target directory for SealedSecrets: {SEALED_SECRETS_DIR}")
    
    if args.dry_run:
        print("Running in DRY-RUN mode (no files will be written)")

    targets = []
    if args.target == "all":
        targets = list(SECRET_MAPPINGS.keys())
    elif args.target == "observer":
        targets = [k for k, v in SECRET_MAPPINGS.items() if "obs" in k]
    elif args.target == "qts":
        targets = [k for k, v in SECRET_MAPPINGS.items() if "qts" in k]

    for filename in targets:
        create_sealed_secret(filename, SECRET_MAPPINGS[filename], dry_run=args.dry_run)

if __name__ == "__main__":
    main()
