require("dotenv").config();

const bcrypt = require("bcryptjs");
const db = require("./db");

async function createAdmin() {
    const {
        ADMIN_CODE,
        ADMIN_NAME,
        ADMIN_EMAIL,
        ADMIN_PASSWORD
    } = process.env;

    if (!ADMIN_CODE || !ADMIN_NAME ||
        !ADMIN_EMAIL || !ADMIN_PASSWORD ||
        !process.env.JWT_SECRET ||
        process.env.JWT_SECRET.length < 32) {
        throw new Error("Configure the admin details and a JWT secret of at least 32 characters in .env");
    }

    if (ADMIN_PASSWORD.length < 12) {
        throw new Error("Use an admin password of at least 12 characters.");
    }

    const [existing] = await db.query(
        "SELECT id FROM users WHERE email = ? OR employee_code = ?",
        [ADMIN_EMAIL, ADMIN_CODE]
    );

    if (existing.length > 0) {
        throw new Error("An account with this email or employee code already exists.");
    }

    const passwordHash = await bcrypt.hash(ADMIN_PASSWORD, 12);

    await db.query(
        `INSERT INTO users
        (employee_code, full_name, email, password_hash, role)
        VALUES (?, ?, ?, ?, 'admin')`,
        [ADMIN_CODE, ADMIN_NAME, ADMIN_EMAIL, passwordHash]
    );

    console.log("Initial admin account created successfully.");
}

createAdmin()
    .catch(error => {
        console.error("Admin creation failed:", error.message);
        process.exitCode = 1;
    })
    .finally(async () => {
        await db.end();
    });