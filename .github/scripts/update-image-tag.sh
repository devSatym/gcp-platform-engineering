#!/usr/bin/env bash
# =============================================================================
# .github/scripts/update-image-tag.sh
#
# Updates image tags in GitOps manifests after a successful build.
# Called by the build workflow to keep Git as the source of truth.
#
# Usage:
#   .github/scripts/update-image-tag.sh <service> <new-tag>
#
# Example:
#   .github/scripts/update-image-tag.sh <service> <new-tag>
#
# This script finds all references to the service's image in gitops/
# and replaces the tag with the new one.
# =============================================================================

set -euo pipefail

SERVICE="${1:?Service name is required}"
NEW_TAG="${2:?New tag is required}"

echo "🏷️  Updating image tag for: ${SERVICE} → ${NEW_TAG}"

# ─── Determine image base path ────────────────────────────────────────────────
# Read from environment or construct from known convention
REGISTRY="${GCP_REGION:-asia-south1}-docker.pkg.dev"
PROJECT_ID="${GCP_PROJECT_ID:-}"
REPO="-e"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "⚠️  GCP_PROJECT_ID not set — skipping image registry update"
  echo "   Set GCP_PROJECT_ID env var to enable registry URL updates"
  exit 0
fi

IMAGE_BASE="${REGISTRY}/${PROJECT_ID}/${REPO}/${SERVICE}"

echo "   Registry: ${REGISTRY}"
echo "   Image:    ${IMAGE_BASE}"
echo "   New tag:  ${NEW_TAG}"

# ─── Update image tags in GitOps values ───────────────────────────────────────
# Pattern: Find lines containing the service image reference and update the tag
UPDATED=0

find gitops/ -name "*.yaml" -o -name "*.yml" | while read -r file; do
  if grep -q "${IMAGE_BASE}:" "${file}" 2>/dev/null; then
    # Replace the tag portion after the colon
    sed -i "s|${IMAGE_BASE}:[^\"' ]*|${IMAGE_BASE}:${NEW_TAG}|g" "${file}"
    echo "   ✓ Updated: ${file}"
    UPDATED=$((UPDATED + 1))
  fi
done

# ─── Update ApplicationSet chart versions (if applicable) ──────────────────
# For Helm-deployed services from Artifact Registry (future)
# This section is a placeholder — expand when custom Helm charts are added
# find gitops/ -name "*.yaml" | xargs grep -l "chart: ${SERVICE}" | while read -r file; do
#   sed -i "s/targetRevision: .*/targetRevision: \"${NEW_TAG}\"/" "${file}"
# done

echo ""
echo "✅ Image tag update complete"
echo "   Affected files will be committed by the build workflow"
