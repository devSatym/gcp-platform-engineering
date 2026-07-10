#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — One-time GCP project bootstrapper
#
# Run this ONCE before any `terraform apply`.
# It sets up the Terraform remote state bucket and the Terraform service account.
#
# Usage:
#   chmod +x bootstrap/bootstrap.sh
#   ./bootstrap/bootstrap.sh
#
# Requirements:
#   - gcloud CLI installed and authenticated
#   - Billing enabled on the GCP project
#   - Owner or Editor rights on the project
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION — Update these before running
# ─────────────────────────────────────────────────────────────────────────────
PROJECT_ID="valiant-house-502004-k2"    # <-- UPDATE THIS
REGION="asia-south1"
TF_STATE_BUCKET="${PROJECT_ID}-tf-state"
TF_SA_NAME="sa-terraform"
TF_SA_EMAIL="${TF_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# ─────────────────────────────────────────────────────────────────────────────
# COLOR OUTPUT
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# PREFLIGHT CHECKS
# ─────────────────────────────────────────────────────────────────────────────
info "Starting bootstrap for project: ${PROJECT_ID}"
echo ""

# Check gcloud is installed
command -v gcloud >/dev/null 2>&1 || error "gcloud CLI not found. Install from https://cloud.google.com/sdk/install"

# Check gcloud is authenticated
gcloud auth list --filter="status:ACTIVE" --format="value(account)" | grep -q "." \
  || error "No active gcloud account. Run: gcloud auth login"

# Verify project exists
gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1 \
  || error "Project '${PROJECT_ID}' not found. Create it first or update PROJECT_ID."

# Set active project
gcloud config set project "${PROJECT_ID}"
success "Active project set to: ${PROJECT_ID}"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1: Enable required APIs
# ─────────────────────────────────────────────────────────────────────────────
echo ""
info "Step 1/4: Enabling required GCP APIs..."

APIS=(
  "cloudresourcemanager.googleapis.com"
  "iam.googleapis.com"
  "storage.googleapis.com"
  "compute.googleapis.com"
)

for api in "${APIS[@]}"; do
  info "  Enabling ${api}..."
  gcloud services enable "${api}" --project="${PROJECT_ID}" --quiet
done

success "APIs enabled."

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2: Create Terraform state bucket
# ─────────────────────────────────────────────────────────────────────────────
echo ""
info "Step 2/4: Creating Terraform state bucket: gs://${TF_STATE_BUCKET}"

if gsutil ls "gs://${TF_STATE_BUCKET}" >/dev/null 2>&1; then
  warn "Bucket gs://${TF_STATE_BUCKET} already exists — skipping creation."
else
  gsutil mb \
    -p "${PROJECT_ID}" \
    -l "${REGION}" \
    -b on \
    "gs://${TF_STATE_BUCKET}"

  # Enable versioning
  gsutil versioning set on "gs://${TF_STATE_BUCKET}"

  # Prevent public access
  gsutil pap set enforced "gs://${TF_STATE_BUCKET}"

  # Lifecycle: delete non-current versions older than 90 days
  cat > /tmp/lifecycle.json <<EOF
{
  "rule": [
    {
      "action": {"type": "Delete"},
      "condition": {
        "numNewerVersions": 5,
        "isLive": false
      }
    }
  ]
}
EOF
  gsutil lifecycle set /tmp/lifecycle.json "gs://${TF_STATE_BUCKET}"
  rm /tmp/lifecycle.json

  success "Terraform state bucket created: gs://${TF_STATE_BUCKET}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3: Create Terraform service account
# ─────────────────────────────────────────────────────────────────────────────
echo ""
info "Step 3/4: Creating Terraform service account: ${TF_SA_EMAIL}"

if gcloud iam service-accounts describe "${TF_SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  warn "Service account ${TF_SA_EMAIL} already exists — skipping creation."
else
  gcloud iam service-accounts create "${TF_SA_NAME}" \
    --display-name="Terraform Service Account" \
    --project="${PROJECT_ID}"

  success "Service account created: ${TF_SA_EMAIL}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4: Grant IAM roles to Terraform SA
# ─────────────────────────────────────────────────────────────────────────────
echo ""
info "Step 4/4: Granting IAM roles to Terraform SA..."

ROLES=(
  "roles/editor"
  "roles/resourcemanager.projectIamAdmin"
  "roles/storage.admin"
  "roles/iam.serviceAccountAdmin"
  "roles/iam.serviceAccountKeyAdmin"
  "roles/serviceusage.serviceUsageAdmin"
)

for role in "${ROLES[@]}"; do
  info "  Binding ${role}..."
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${TF_SA_EMAIL}" \
    --role="${role}" \
    --quiet > /dev/null
done

success "IAM roles granted."

# ─────────────────────────────────────────────────────────────────────────────
# GRANT TERRAFORM SA ACCESS TO STATE BUCKET
# ─────────────────────────────────────────────────────────────────────────────
gsutil iam ch \
  "serviceAccount:${TF_SA_EMAIL}:roles/storage.objectAdmin" \
  "gs://${TF_STATE_BUCKET}"

success "Terraform SA granted access to state bucket."

# ─────────────────────────────────────────────────────────────────────────────
# DONE — Print next steps
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "${GREEN}Bootstrap complete!${NC}"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo ""
echo "  1. Authenticate Terraform as the SA:"
echo "     gcloud iam service-accounts keys create /tmp/sa-terraform-key.json \\"
echo "       --iam-account=${TF_SA_EMAIL}"
echo "     export GOOGLE_APPLICATION_CREDENTIALS=/tmp/sa-terraform-key.json"
echo ""
echo "  2. Update your tfvars and backend files:"
echo "     terraform/environments/dev/terraform.tfvars → project_id = \"${PROJECT_ID}\""
echo "     terraform/environments/dev/backend.tf       → bucket = \"${TF_STATE_BUCKET}\""
echo ""
echo "  3. Initialize and apply:"
echo "     cd terraform/environments/dev"
echo "     terraform init"
echo "     terraform plan"
echo "     terraform apply"
echo ""
echo -e "${YELLOW}IMPORTANT:${NC} Store the SA key securely. Delete it after configuring"
echo "Workload Identity Federation in Phase 6 for keyless authentication."
echo ""
