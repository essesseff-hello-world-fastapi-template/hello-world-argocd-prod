# hello-world - Argo CD Application (PROD)

This repository contains the Argo CD Application manifest for the **PROD** environment of the hello-world essesseff™ app.  

It is ***not necessary*** to be an essesseff™ subscriber in order to make use of the standardized
pattern and automation offered in this and corresponding code and config repositories for
configuring and managing your FastAPI application to follow said standardized pattern of development, build, deployment and promotion through DEV -> QA -> STAGING -> PROD environments, although it should not surprise you that it will be much easier for essesseff™ subscribers to do so.

*Please Note:*

*essesseff™ is an independent DevOps ALM PaaS-as-SaaS and is in no way affiliated with, endorsed by, sponsored by, or otherwise connected to GitHub® or The Linux Foundation®.* 

*essesseff™ is a trademark of essesseff LLC.*

*GITHUB®, the GITHUB® logo design and the INVERTOCAT logo design are trademarks of GitHub, Inc., registered in the United States and other countries.*

*Argo®, Helm®, Kubernetes® and K8s® are registered trademarks of The Linux Foundation.*

## See Also

- [essesseff Documentation](https://essesseff.com/docs) - essesseff platform documentation
- [Argo CD Documentation](https://argo-cd.readthedocs.io/) - Argo CD documentation
- [Helm Documentation](https://helm.sh/docs) - Helm documentation
- [Kubernetes Documentation](https://kubernetes.io/docs/home/) - Kubernetes (K8s) documentation
- [GitHub Documentation](https://docs.github.com/en) - GitHub documentation

## Repository Structure

```
hello-world-argocd-prod/
├── app-of-apps.yaml.template                      # Root Application template
├── argocd/
│   └── hello-world-prod-application.yaml.template # PROD environment Application manifest (auto-synced) template
├── argocd-repository-secret.yaml.template         # Argo CD repository secrets template
├── ghcr-credentials-secret.yaml.template          # GHCR credentials (set once per K8s cluster for organization) template
├── notifications-configmap.yaml.template          # Argo CD notifications configuration template
├── offboarding/
│   └── offboard-essesseff-hello-world-fastapi-template.sh # script for offboarding the {{K8S_NAMESPACE}} namespace from K8s
│   └── offboard-hello-world-prod.sh                  # script for offboarding the hello-world prod app 1) from essesseff only or 2) from Argo CD and K8s entirely
├── setup-argocd-cluster.sh           # Argo CD K8s setup script 
├── setup-argocd.sh                   # Argo CD hello-world-prod essesseff app setup script 
└── README.md                         # This file
```

## Architecture

- **Deployment Model**: Trunk-based development (single `main` branch)
- **Deploy**: Promote, re-deploy and rollback (via essesseff UX).  For non-essesseff subscribers and for otherwise strictly GitOps deployments, PROD deployments and code promotions can be accomplished through commit(s) to the config-prod repo, in particular the Helm Chart.yaml and values.yaml.
- **GitOps**: Managed by Argo CD with automated sync

## Quick Start

### (if not done already) Deploy/Configure Argo CD on the Environment-specific Kubernetes Cluster 

1. **Run Argo CD cluster setup script**:
```bash
   chmod 744 setup-argocd-cluster.sh
   ./setup-argocd-cluster.sh
   ```
   
### Configure hello-world-prod essesseff App to Argo CD and deploy to K8s

1. **Git Clone This Repository**:
   ```bash
   git clone git@github.com:essesseff-hello-world-fastapi-template/hello-world-argocd-prod.git
   ```
   
2. **Configure Environment Variables in .env File**:
   ```bash
   cp env.example .env
   ```
   Then set the environment variables in the .env which will be used for generating the following from the templates in this repository:

      a. ***Configuration of Argo CD repository access***:
   
      argocd-repository-secret.yaml with your GitHub Argo CD machine username and token
   
      This creates secrets for Argo CD to access:
      - `hello-world-argocd-prod` repository (to read Application manifests)
      - `hello-world-config-prod` repository (to read Helm charts and values)

      b. ***Configuration of Argo CD access to GitHub Container Registry (GHCR)***:
   
      ghcr-credentials-secret.yaml with your GitHub Argo CD machine username, token, email, and base64 credentials

      c. ***Configuration of hello-world-prod Deployment in Argo CD***:

      hello-world-prod-application.yaml is used to configure the hello-world-prod deployment

      d. ***Configuration of hello-world-argocd-prod App-of-Apps Deployment in Argo CD***:

      app-of-apps.yaml is used to configure the hello-world-argocd-prod app-of-apps deployment

      e. ***Configuration of hello-world-prod Argo CD Notifications to essesseff***:

      If notifications-secret.yaml is downloaded from essesseff for hello-world-prod, notifications-configmap.yaml will be used to configure Argo CD notifications to essesseff.
   
      **Note**: This secret can be set once for the entire GitHub organization / K8s namespace and will be used by Argo CD to pull container images from GHCR for all environments. You do not need to create separate secrets for each environment repository but should set the ghcr-credentials secret at least once per K8s namespace in each relevant K8s cluster.  *If the ghcr-credentials-secret.yaml.template file is not present, the setup-argocd.sh script will assume that the ghcr-credentials secret is already set for the given K8s namespace on the env-specific K8s cluster and move on.*

3. **(if an essesseff-subscribed app) Configure Argo CD Notifications Secrets**:

   Request the notifications-secret.yaml file contents from the essesseff UX for hello-world here:
   https://www.essesseff.com/home/[YOUR_essesseff_TEAM_ACCOUNT]/apps/hello-world/settings

   Copy the downloaded file to ./notifications-secret.yaml 

4. **Run the setup-argocd.sh Script**:
   ```bash
   chmod 744 setup-argocd.sh
   ./setup-argocd.sh
   ```

   This script applies all secrets, configmaps, Argo CD application definitions, etc. for hello-world PROD.

5. **Verify in Argo CD UI**:
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   # Access: https://localhost:8080
   ```
   
   You should see:
   - `hello-world-argocd-prod` - Root Application (watches this repository)
   - `hello-world-prod` - Environment Application (auto-synced by root Application)

6. **Access the Deployed Application**:
   ```bash
   kubectl port-forward service/hello-world-prod 8081:80 -n essesseff-hello-world-fastapi-template
   # Access: http://localhost:8081
   ```
### How to Offboard hello-world-prod Deployment from Argo CD and K8s

1. **Execute the offboarding script**:
   ```bash
   cd offboarding
   chmod 744 offboard-hello-world-prod.sh
   ./offboard-hello-world-prod.sh
   ```

### How to Offboard {{K8S_NAMESPACE}} K8s Namespace and All of its Resources

1. **Execute the offboarding script**:
   ```bash
   cd offboarding
   chmod 744 offboard-essesseff-hello-world-fastapi-template.sh
   ./offboard-essesseff-hello-world-fastapi-template.sh
   ```

## Application Details

- **Name**: `hello-world-prod`
- **Namespace**: `argocd`
- **Source Repository**: `hello-world-config-prod`
- **Destination Namespace**: `{{K8S_NAMESPACE}}`
- **Sync Policy**: Automated with prune and self-heal enabled

## Deployment Process

### PROD Code Promotion Deployment (essesseff-Subscribed App)

1. QA or DevOps Engineer declares QA deployment STABLE in essesseff UX
2. Release Engineer deploys STABLE release to PROD in essesseff UX
3. essesseff GitHub App automation triggers essesseff to auto-update Helm `hello-world-config-prod/Chart.yaml` and `hello-world-config-prod/values.yaml` with the image tag of the newly built image
4. Argo CD syncs PROD Application automatically on K8s

### Manual GitOps Deployment

1. Push update(s) to the `main` branch in `hello-world-config-prod` repository, typically to Helm Chart.yaml and/or values.yaml
2. Argo CD syncs PROD Application automatically on K8s

## Repository URLs

- **Source**: `https://github.com/essesseff-hello-world-fastapi-template/hello-world`
- **Config PROD**: `https://github.com/essesseff-hello-world-fastapi-template/hello-world-config-prod`
- **Argo CD PROD**: `https://github.com/essesseff-hello-world-fastapi-template/hello-world-argocd-prod` (this repo)

## essesseff Integration

This setup requires the essesseff platform for automated deployment orchestration:

- **Decision-driven promotions**: PROD deployment executed by Release Engineer of STABLE release via essesseff UX
- **RBAC enforcement**: Role-based access control for code and config development, build, deployment, promotion, etc.
- **Audit trail**: Complete history of all builds, deployments, promotions, etc.

## Argo CD Configuration

### Reduce Git Polling Interval (Optional)

By default, Argo CD polls Git repositories every ~3 minutes (120-180 seconds). To reduce this to, for example, 30 seconds for faster change detection:

```bash
kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"timeout.reconciliation":"30s","timeout.reconciliation.jitter":"10s"}}'
```

This will:
- Set base polling interval to 30 seconds
- Add up to 10 seconds of jitter (total: 30-40 seconds)
- Allow Argo CD to detect changes in `argocd/hello-world-prod-application.yaml` more quickly

## How It Works

1. **essesseff manages** image lifecycle and promotion decisions
2. **essesseff updates** Helm `Chart.yaml` and `values.yaml` files in config repos with approved image tags
3. **Argo CD detects** changes via Git polling (default: ~3 minutes, configurable to 30 seconds, as in the example above, or to the interval of your choosing)
4. **Argo CD syncs** Application automatically (auto-sync enabled)
5. **Kubernetes resources** are updated with new image versions and/or configuration settings as per Helm chart and overrides i.e. values.yaml settings

## See Also

- [essesseff Documentation](https://essesseff.com/docs) - essesseff platform documentation
- [Argo CD Documentation](https://argo-cd.readthedocs.io/) - Argo CD documentation
- [Helm Documentation](https://helm.sh/docs) - Helm documentation
- [Kubernetes Documentation](https://kubernetes.io/docs/home/) - Kubernetes (K8s) documentation
- [GitHub Documentation](https://docs.github.com/en) - GitHub documentation
  
## Disclaimer
This software is provided "as is", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.

Use at your own risk. The maintainers of this project make no guarantees about its functionality, security, or suitability for any purpose.
