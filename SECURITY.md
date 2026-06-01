# Security Policy

## Secrets

Do not commit real `.env` files, API keys, JWT secrets, database passwords, or AWS credentials.

Use these files only as templates:

- `.env.example`
- `.env.production.example`
- `backend/.env.example`
- `backend/.env.production.example`

Production secrets should be stored in AWS Secrets Manager or another managed secret store.

## Reporting a Vulnerability

If you find a security issue, do not open a public issue with exploitable details. Contact the repository owner privately and include:

- affected service or file
- reproduction steps
- impact
- suggested fix, if known
