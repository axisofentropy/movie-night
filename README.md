# movie-night
Stream movies to friends via ~*cOnTaInErS*~

This is mostly for me to try working with Large Language Models. Assume a majority of this repository was "vibe coded", starting with the instructions below:

---

## 1. Prerequisites

Before you begin, ensure you have the following tools installed on your local machine:

- Git
- Google Cloud CLI (`gcloud`)
- Terraform

## 2. Create and Configure the GCP Project

First, you'll create the new project and link it to a billing account.

Log in to Google Cloud:

```console
gcloud auth login
```

Create the GCP Project:

```console
gcloud projects create example-movie-night --name="Movie Night"
```

Set Your New Project as the Default:

```console
gcloud config set project example-movie-night
```

Link a Billing Account (Manual Step): This is a critical step that must be done in the Google Cloud Console.

Go to the Google Cloud Billing Console.

Select your new "Movie Night" project.

Follow the prompts to link it to your billing account. Terraform will fail if the project is not associated with an active billing account.

## 3. Set Up Your Local Environment
Now, clone your repository and create a local override file for Terraform.

Clone Your GitHub Repository:

```console
git clone <your-github-repository-url>
cd <your-repository-directory>
```

Create a Local Terraform Variables File: Create a new file named `terraform.tfvars`. This file is automatically used by Terraform to override variables from `variables.tf` and should NOT be committed to Git.

Add the following content to `terraform.tfvars`:

```yaml
gcp_project_id = "example-movie-night"
```

This tells Terraform to use your new project ID instead of the default one in your main configuration.

## 4. Create Secrets and Authenticate

Before running Terraform, you must create your secrets and authenticate your local environment.

Enable the Secret Manager and Storage API's:

```console
gcloud services enable secretmanager.googleapis.com
gcloud services enable storage-api.googleapis.com
```

Create the GoDaddy API Key Secret:

```console
echo "your_godaddy_api_key_here" | gcloud secrets create godaddy-api-key --data-file=-
```

Create the Webhook Secret Token:

```console
openssl rand -hex 16 | gcloud secrets create webhook-secret-token --data-file=-
```

Provide Application Default Credentials for Terraform:

```console
gcloud auth application-default login
```

Create storage bucket for Terraform state and enable versioning:

```console
gcloud storage buckets create gs://example-movie-night-tfstate
gcloud storage buckets update gs://example-movie-night-tfstate --versioning
```

## 5. Deploy with Terraform

You are now ready to initialize and apply your Terraform configuration.

Initialize Terraform: This downloads the necessary Google Cloud provider plugin.

```console
terraform init
```

Plan the Deployment: This performs a dry run, showing you all the resources that will be created. It will first enable the required APIs, which may take a minute.

```console
terraform plan
```

Apply the Configuration: This will build all the resources defined in your .tf files.

```console
terraform apply
```

Terraform will show you the plan again and ask for confirmation. Type yes and press Enter to proceed. The process will take a few minutes to complete.

Once terraform apply finishes successfully, your entire infrastructure—including the GCS bucket, service account, instance template, and firewall rules—will be live and ready. You can then scale your instance group to 1 to start the movie night VM.

```console
gcloud compute instance-groups managed resize movie-night-mig \
    --size=1 \
    --zone=us-east1-b
```

Download a movie file to the VM by making an HTTP POST request to the webhook service:

```console
curl -X POST https://movienight.example.com:4443/movie/download \
  -H "X-Auth-Token: $(gcloud secrets versions access latest --secret="webhook-secret-token" --project="example-movie-night")" \
  -H "Content-Type: text/plain" \
  --data-raw 'https://archive.org/download/public-domain-archive/Space%20Shuttle%20Launch%20_%20Free%20Public%20Domain%20Video%281080P_HD%29.mp4'
```

Start streaming the movie:

```console
curl -X POST https://movienight.example.com:4443/movie/start \
  -H "X-Auth-Token: $(gcloud secrets versions access latest --secret="webhook-secret-token" --project="example-movie-night")"
```

You and your friends can watch the movie together in most web browsers: https://movienight.example.com/stream

Stop the server when you're done:

```console
gcloud compute instance-groups managed resize movie-projector-mig --size=0 --zone=us-east1-b
```