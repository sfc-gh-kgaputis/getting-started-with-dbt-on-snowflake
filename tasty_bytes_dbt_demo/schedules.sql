-- To avoid issues with CREATE OR ALTER, suspend all of the tasks from root to child
-- ALTER TASK IF EXISTS ensures this file can execute on first run each time a task is added
ALTER TASK IF EXISTS run_tasty_bytes_subset SUSPEND;
ALTER TASK IF EXISTS run_tasty_bytes_full SUSPEND;

-- Builds a subset of the models run tests. This is an example of a subset that needs to be available early for business needs
CREATE OR ALTER TASK run_tasty_bytes_subset
  WAREHOUSE = tasty_bytes_dbt_wh
  SCHEDULE = '12 hours'
  AS
      execute dbt project tasty_bytes_prod_dbt_project args='build --select +customer_loyalty_metrics --target prod';

-- Builds all models and runs tests in DAG order, failing early if any test fails
CREATE OR ALTER TASK run_tasty_bytes_full
  WAREHOUSE = tasty_bytes_dbt_wh
  AFTER run_tasty_bytes_subset
  AS
      execute dbt project tasty_bytes_prod_dbt_project args='build --target prod';

-- When a task is first created or if an existing task it paused, it MUST BE RESUMED to be activated
-- The tasks must be enabled in REVERSE ORDER from child to root
ALTER TASK IF EXISTS run_tasty_bytes_full RESUME;
ALTER TASK IF EXISTS run_tasty_bytes_subset RESUME;
