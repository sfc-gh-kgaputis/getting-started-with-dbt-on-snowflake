-- To avoid issues with CREATE OR ALTER, suspend all of the tasks from root to child
-- ALTER TASK IF EXISTS ensures this file can execute on first run each time a task is added
ALTER TASK IF EXISTS tasty_bytes_dbt_prod_refresh_subset SUSPEND;
ALTER TASK IF EXISTS tasty_bytes_dbt_prod_refresh_full SUSPEND;

-- Builds a subset of the models run tests. This is an example of a subset that needs to be available early for business needs
CREATE OR ALTER TASK tasty_bytes_dbt_prod_refresh_subset
  WAREHOUSE = tasty_bytes_dbt_wh
  SCHEDULE = '12 hours'
  AS
      execute dbt project tasty_bytes_dbt_db.public.tasty_bytes_dbt_prod args='build --select +customer_loyalty_metrics --target prod';

-- Builds all models and runs tests in DAG order, failing early if any test fails
CREATE OR ALTER TASK tasty_bytes_dbt_prod_refresh_full
  WAREHOUSE = tasty_bytes_dbt_wh
  AFTER tasty_bytes_dbt_prod_refresh_subset
  AS
      execute dbt project tasty_bytes_dbt_db.public.tasty_bytes_dbt_prod args='build --target prod';

-- When a task is first created or if an existing task it paused, it MUST BE RESUMED to be activated
-- The tasks must be enabled in REVERSE ORDER from child to root
ALTER TASK IF EXISTS tasty_bytes_dbt_prod_refresh_full RESUME;
ALTER TASK IF EXISTS tasty_bytes_dbt_prod_refresh_subset RESUME;
