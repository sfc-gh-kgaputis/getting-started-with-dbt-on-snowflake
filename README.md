# Getting Started with dbt Projects on Snowflake

## Overview

This repository contains an example dbt project for [dbt Projects on Snowflake](https://docs.snowflake.com/en/user-guide/data-engineering/dbt-projects-on-snowflake). It uses the fictitious **Tasty Bytes** food truck brand as sample data and walks through environment setup, data modeling, CI/CD, and scheduling — all running natively inside Snowflake.

This repository is based on these Snowflake tutorials:
- [Get started with dbt Projects on Snowflake](https://docs.snowflake.com/en/user-guide/tutorials/dbt-projects-on-snowflake-getting-started-tutorial)
- [Set up CI/CD for dbt Projects on Snowflake](https://docs.snowflake.com/en/user-guide/tutorials/dbt-projects-on-snowflake-ci-cd-tutorial)

## What's Included

### Setup Scripts (`setup/`)

- **`tasty_bytes_setup.sql`** — Creates the warehouse, database, schemas, GitHub integration, network rules, and loads the Tasty Bytes source data from S3 into raw tables.
- **`ci_cd_setup.sql`** — Creates three GitHub Actions service users with OIDC authentication (one per workflow context: PR CI, integration, prod) and optional network policies for CI/CD pipelines.

### dbt Project (`tasty_bytes_dbt_demo/`)

- **Staging models** — Views that clean and rename columns from raw source tables (orders, trucks, menus, locations, franchises, customer loyalty).
- **Mart models** — Tables that aggregate business metrics: `orders`, `customer_loyalty_metrics`, and `sales_metrics_by_location` (Python model).
- **Custom macros** — Schema name generation for multi-environment deployments.
- **Generic tests** — Reusable test for validating positive amounts.

### dbt Targets (`profiles.yml`)

Four targets map to distinct schemas:

| Target | Schema | Purpose |
|--------|--------|---------|
| `dev` | `DBT_DEV_<username>` | Per-developer local iteration (Snowflake Workspaces) |
| `ci` | `DBT_CI_PR_<number>` | Isolated compile on every pull request; ready for future materialization |
| `integration` | `dev` | Full deploy automatically run on every merge to `main` |
| `prod` | `prod` | Stable production data; promoted manually with approval |

### CI/CD (`.github/workflows/`)

Three-stage pipeline using Snowflake OIDC — no stored credentials required:

| Workflow | Trigger | OIDC Subject | Stage |
|----------|---------|--------------|-------|
| `incoming_pr.yml` | PR opened / updated against `main` | `repo:<org>/<repo>:pull_request` | Automatic validation |
| `pr_merged.yml` | Push to `main` | `repo:<org>/<repo>:ref:refs/heads/main` | Automatic integration deploy + test |
| `promote_prod.yml` | Manual (`workflow_dispatch`) | `repo:<org>/<repo>:environment:prod` | Manual production promotion |

Each workflow uses a dedicated Snowflake OIDC service user matched by its `WORKLOAD_IDENTITY SUBJECT`. Only `promote_prod.yml` requires a GitHub environment (`prod`); the other two match event-based subjects (`pull_request` and `ref:refs/heads/main`) without a declared environment. Configure the `prod` GitHub environment with **required reviewers** to gate production deployments.

Pull request CI is dynamic. PR `123` deploys a dbt project object named `TASTY_BYTES_DBT_CI_PR_123` and targets schema `TASTY_BYTES_DBT_DB.DBT_CI_PR_123`. Different PRs can validate concurrently, while updates and cleanup for the same PR remain serialized. CI currently runs `dbt compile`, so it does not materialize models; the schema name is configured now so changing the workflow command from `compile` to `build` later enables isolated materialization without redesigning CI. When the PR closes, the workflow drops both the project object and the schema if it exists.

The shared integration environment intentionally uses `TASTY_BYTES_DBT_DB.DEV`. This is separate from personal development schemas, which use `TASTY_BYTES_DBT_DB.DBT_DEV_<username>`.

### Scheduling (`schedules.sql`)

Task definitions for running the production dbt project object (`tasty_bytes_prod_dbt_project`) on a schedule using Snowflake Tasks. Applied automatically by `promote_prod.yml`.

## Quick Start

1. Fork this repository.
2. Run `tasty_bytes_setup.sql` in a Snowflake worksheet to create the environment and load source data.
3. Run `ci_cd_setup.sql` to create the three OIDC service users (replace `your_repo_org/your_dbt_repo` with your fork's org and repo name).
4. In GitHub, create one **Environment** named `prod`. Add required reviewers to gate production promotions.
5. Add these repository-level **Variables** (Settings → Secrets and variables → Actions → Variables):
   - `SNOWFLAKE_ACCOUNT` — your Snowflake account identifier.
   - `SNOWFLAKE_DATABASE` — `TASTY_BYTES_DBT_DB`.
   - `SNOWFLAKE_SCHEMA` — `PUBLIC`, where the schema-level dbt project objects and production tasks are managed.
   - `SNOWFLAKE_ROLE` — `ACCOUNTADMIN` for this tutorial; replace it with least-privilege stage roles later.
   - `SNOWFLAKE_WAREHOUSE` — `TASTY_BYTES_DBT_WH`.
6. Create a [workspace in Snowsight](https://docs.snowflake.com/en/user-guide/ui-snowsight/workspaces) connected to your fork and run `dbt deps`, then `dbt build` locally.

The tutorial setup grants `ACCOUNTADMIN` to the three service users for simplicity. Replace that with dedicated least-privilege CI, integration, and production roles before using this pattern for production workloads.

## Environment Operation

### Personal development

1. Open a Snowflake Workspace connected to your branch.
2. Select the `dev` environment and run `dbt deps` when dependencies change.
3. Run `dbt build` for local iteration.
4. Models are written to `TASTY_BYTES_DBT_DB.DBT_DEV_<YOUR_USERNAME>`.

Personal development does not use a GitHub environment or GitHub OIDC user; it runs as the developer's Snowflake identity.

### Pull request CI

Opening or updating a PR against `main` automatically:

1. Authenticates as `github_actions_ci_user` using OIDC subject `repo:<org>/<repo>:pull_request`.
2. Deploys `TASTY_BYTES_DBT_CI_PR_<number>`.
3. Runs `compile --target ci` with `DBT_SCHEMA=DBT_CI_PR_<number>`.
4. Drops the project object and schema when the PR closes.

No GitHub environment is required. To enable materialization later, replace `compile` with `build` in `incoming_pr.yml`; the PR-specific schema and teardown are already configured.

Compile-only CI does not execute model SQL or data tests, so it will not catch runtime data or permission failures. Those are currently covered by the integration `build` after merge.

### Shared integration

Merging to `main` automatically:

1. Authenticates as `github_actions_integration_user` using OIDC subject `repo:<org>/<repo>:ref:refs/heads/main`.
2. Deploys the stable `tasty_bytes_dbt_integration` project object.
3. Runs `build --target integration` into `TASTY_BYTES_DBT_DB.DEV`.

No GitHub environment is required for integration.

### Production

Run `promote_prod.yml` manually with a commit SHA already validated in integration. The `prod` GitHub environment requires reviewer approval and produces OIDC subject `repo:<org>/<repo>:environment:prod`. The workflow builds into `TASTY_BYTES_DBT_DB.PROD` and applies the production schedules.
