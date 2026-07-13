import os
import boto3
from botocore.config import Config

account_id = os.environ.get('R2_ACCOUNT_ID')
access_key = os.environ.get('R2_ACCESS_KEY_ID')
secret_key = os.environ.get('R2_SECRET_ACCESS_KEY')
bucket_name = os.environ.get('R2_BUCKET')

if not all([account_id, access_key, secret_key, bucket_name]):
    print("⚠️ Missing R2 configuration in .env. Skipping upload.")
    exit(0)

s3 = boto3.client(
    's3',
    endpoint_url=f'https://{account_id}.r2.cloudflarestorage.com',
    aws_access_key_id=access_key,
    aws_secret_access_key=secret_key,
    config=Config(signature_version='s3v4')
)

files_to_upload = [
    'landingpage/assets/BerryShot.dmg',
    'landingpage/assets/version.json',
    'landingpage/assets/BerryShot.dmg.sha256'
]

for file_path in files_to_upload:
    if os.path.exists(file_path):
        filename = os.path.basename(file_path)
        print(f"Uploading {file_path} to R2 bucket {bucket_name} as {filename}...")
        try:
            s3.upload_file(file_path, bucket_name, filename)
            print(f"✅ Uploaded {filename}")
        except Exception as e:
            print(f"❌ Failed to upload {filename}: {e}")
            exit(1)
    else:
        print(f"⚠️ {file_path} not found.")

print("🎉 R2 Upload Complete!")
