-- ICT371 Advanced Database - Mulungushi University
-- Student: Augustine lukaki (202306775)
-- Question 6: Monthly Payroll Processing
-- PostgreSQL / PL/pgSQL

-- Gross pay = basic salary + allowance. Net pay = gross pay - deduction. The unique
-- employee/month key and ON CONFLICT DO NOTHING preserve existing payroll records on
-- reruns.

-- ============================================================
-- 6(a) Tables and seed data
-- pay_month is constrained to the first day of a month. Money inputs cannot be negative.

CREATE TABLE employees (
 employee_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 full_name VARCHAR(120) NOT NULL,
 basic_salary NUMERIC(12,2) NOT NULL CHECK(basic_salary>=0),
 allowance NUMERIC(12,2) NOT NULL CHECK(allowance>=0),
 deduction NUMERIC(12,2) NOT NULL CHECK(deduction>=0),
 active BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE TABLE payroll (
 payroll_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 pay_month DATE NOT NULL CHECK(EXTRACT(DAY FROM pay_month)=1),
 gross_pay NUMERIC(12,2) NOT NULL,net_pay NUMERIC(12,2) NOT NULL,
 UNIQUE(employee_id,pay_month)
);
CREATE TABLE salary_audit (
 audit_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
 old_salary NUMERIC(12,2) NOT NULL,new_salary NUMERIC(12,2) NOT NULL,
 changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO employees(full_name,basic_salary,allowance,deduction,active) VALUES
 ('Alice',5000,500,300,TRUE),('Brian',4200,300,250,TRUE),
 ('Chipo',3800,200,200,FALSE);

-- ============================================================
-- 6(b) Net-pay function
-- Rejects unknown employees and negative computed net pay.

CREATE OR REPLACE FUNCTION fn_net_pay(p_employee_id BIGINT)
RETURNS NUMERIC(12,2) LANGUAGE plpgsql AS $$
DECLARE v_basic NUMERIC(12,2);v_allow NUMERIC(12,2);v_deduct NUMERIC(12,2);v_net NUMERIC(12,2);
BEGIN
 SELECT basic_salary,allowance,deduction INTO v_basic,v_allow,v_deduct
 FROM employees WHERE employee_id=p_employee_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown employee'; END IF;
 v_net:=v_basic+v_allow-v_deduct;
 IF v_net<0 THEN RAISE EXCEPTION 'Computed net pay is negative'; END IF;
 RETURN v_net;
END; $$;

-- ============================================================
-- 6(c) Payroll procedure
-- A query FOR loop processes active employees. Any exception aborts the call; existing
-- rows are not changed.

CREATE OR REPLACE PROCEDURE pr_process_payroll(p_month DATE)
LANGUAGE plpgsql AS $$
DECLARE e RECORD; v_gross NUMERIC(12,2);v_net NUMERIC(12,2);
BEGIN
 IF p_month IS NULL OR EXTRACT(DAY FROM p_month)<>1 THEN
  RAISE EXCEPTION 'Pay month must be the first day of a month';
 END IF;
 FOR e IN SELECT employee_id,basic_salary,allowance FROM employees WHERE active LOOP
  v_gross:=e.basic_salary+e.allowance;
  v_net:=fn_net_pay(e.employee_id);
  INSERT INTO payroll(employee_id,pay_month,gross_pay,net_pay)
  VALUES(e.employee_id,p_month,v_gross,v_net)
  ON CONFLICT(employee_id,pay_month) DO NOTHING;
 END LOOP;
END; $$;
CALL pr_process_payroll(DATE '2026-10-01');
CALL pr_process_payroll(DATE '2026-11-01');

-- ============================================================
-- 6(d) Salary audit trigger
-- Logs only an actual basic_salary change.

CREATE OR REPLACE FUNCTION fn_audit_salary()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.basic_salary IS DISTINCT FROM OLD.basic_salary THEN
  INSERT INTO salary_audit(employee_id,old_salary,new_salary)
  VALUES(NEW.employee_id,OLD.basic_salary,NEW.basic_salary);
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER trg_salary_audit
AFTER UPDATE OF basic_salary ON employees FOR EACH ROW
EXECUTE FUNCTION fn_audit_salary();

-- ============================================================
-- 6(e) Payroll report view
-- No filter on employees.active is used, so historical payroll for employees later made
-- inactive remains visible.

CREATE OR REPLACE VIEW v_payroll_report AS
SELECT e.full_name,p.pay_month,p.gross_pay,p.net_pay
FROM payroll p JOIN employees e USING(employee_id);

-- ============================================================
-- 6(f) Pay-month index
-- The unique index on (employee_id,pay_month) is not suitable as a leading-key index for
-- pay_month-only reports.

CREATE INDEX idx_payroll_month ON payroll(pay_month);
EXPLAIN SELECT employee_id,gross_pay,net_pay
FROM payroll WHERE pay_month=DATE '2026-11-01';

-- ============================================================
-- 6(g) Monthly schedule and job inspection
-- Runs at 02:00 on day 1 and passes the first day of the previous month. The schedule is
-- set up to run monthly.

CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('monthly-payroll',
 '0 2 1 * *',
 $$CALL pr_process_payroll(date_trunc('month',CURRENT_DATE - INTERVAL '1 month')::date)$$);
-- Inspect scheduled jobs:
SELECT jobid,jobname,schedule,command,active FROM cron.job;
-- Inspect execution history (availability depends on pg_cron version/configuration):
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 20;
