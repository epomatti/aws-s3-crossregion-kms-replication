# S3 Cross-Region replication

Configuration details:

- SSE-KMS replication: Enabled
- Replication Time Control (RTC): Enabled
- Metrics: Enabled
- Delete Marker Replication: Enabled

To start, setup a `.auto.tfvars`:

```terraform
primary_aws_region   = "sa-east-1"
secondary_aws_region = "us-east-2"
```

Create the infrastructure:

```
terraform init
terraform apply
```

To test it, upload a file to the Primary bucket.

```sh
aws s3api put-object --bucket bucket-primary-eap --key replicate/file.txt --body file.txt
```

Metrics are enabled for monitoring.
