CREATE TABLE patients_public (
    patient_id integer PRIMARY KEY,
    full_name text NOT NULL,
    phone text,
    email text,
    address text,
    emergency_contact text
);
