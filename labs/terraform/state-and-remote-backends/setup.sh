mkdir -p sample infra
cat > sample/terraform.tfstate << 'EOF'
{
  "version": 4,
  "terraform_version": "1.10.0",
  "serial": 7,
  "lineage": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "outputs": {},
  "resources": [
    {
      "mode": "managed",
      "type": "aws_s3_bucket",
      "name": "app_assets",
      "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
      "instances": [
        {
          "schema_version": 0,
          "attributes": {
            "arn": "arn:aws:s3:::example-app-assets-sandbox",
            "bucket": "example-app-assets-sandbox",
            "id": "example-app-assets-sandbox"
          }
        }
      ]
    }
  ]
}
EOF
rm -f serial.txt .gitignore infra/backend.tf
