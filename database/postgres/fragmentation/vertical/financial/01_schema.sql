CREATE TABLE patients_financial (
    patient_id integer PRIMARY KEY,
    insurance_provider text,
    insurance_number text,
    billing_status text,
    outstanding_balance numeric(12, 2),
    payment_method text
);
