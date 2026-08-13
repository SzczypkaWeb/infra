Require pull request before merging + Require approvals

## 2026-08-XX — Migrated backend hosting from AWS (ECS Fargate + RDS) to GCP (Cloud Run + Supabase)

**Decision:** Destroyed the AWS ECS Fargate service and RDS instance; backend now runs on GCP Cloud Run with Supabase (managed Postgres) as the database. AWS Terraform module kept in the repo (not deleted) as a reference/portfolio artifact — can be recreated via `terraform apply` in minutes if needed.

**Why:** ECS Fargate + RDS bill by the hour regardless of traffic, which doesn't make sense for a low-traffic portfolio project. Cloud Run scales to zero (Always Free: 2M requests/month, no expiry) and Supabase's free tier has no 12-month cliff (unlike RDS or Azure Database for PostgreSQL). Net effect: near-$0 ongoing cost instead of a recurring AWS bill.

**Trade-off accepted:** Supabase free-tier projects pause after 7 days of inactivity and need a manual resume from the dashboard — acceptable for a project that isn't live 24/7 in front of real users.

**Auth model note:** GitHub → GCP auth uses Workload Identity Federation (attribute-condition on the `repository` claim), distinct from the AWS OIDC + IAM role trust policy setup — kept both configs in version control as evidence of understanding two different federation models, not just one copy-pasted twice.