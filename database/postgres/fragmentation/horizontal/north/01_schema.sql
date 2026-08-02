CREATE TABLE patients (
    patient_id integer PRIMARY KEY,
    full_name text NOT NULL,
    phone text,
    email text,
    address text,
    region text NOT NULL,
    CONSTRAINT patients_region_check CHECK (region = 'NORTH')
);
