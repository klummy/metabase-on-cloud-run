# Metabase on Cloud Run

Steps

- Replace `<db-connection-name>` in `docker/startup.sh` with your Cloud SQL instance connection name
- Build and deploy the image to Artifact registry

```sh
# Prerequisite - Install docker
# Prerequisite - authenticate to Artifact registry docker: https://cloud.google.com/artifact-registry/docs/docker/pushing-and-pulling#auth

cd ./docker

# Build image
docker build . -t <project_region></project_region>-docker.pkg.dev/<project_id>/metabase/metabase

# Deploy image
docker push <project_region></project_region>-docker.pkg.dev/<project_id>/metabase/metabase
```

- Set the variables in `variables.tf` or pass them from the TF execution platform e.g. CLI or Terraform Cloud
- Run `terraform init`
- Run `terraform apply`
- Visit your GCP project and navigate to Cloud Run to see the Metabase service


- Note: The initial deployment sometimes takes a while to start up which may exceed the default timeout of 300 seconds. If this happens, you can manually deploy a new revision of the service from the Cloud Run console with an higher timeout value e.g. 6000 seconds. This will allow the service to start up and then you can revert the timeout value back to 300 seconds when another TF plan/apply is done

