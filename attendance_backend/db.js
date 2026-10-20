
const mysql = require("mysql2");

const cloudMode = process.env.DB_MODE === "cloud";

const db = mysql.createPool({
    host: cloudMode
        ? process.env.DB_HOST
        : (process.env.DB_HOST || "localhost"),

    port: Number(
        process.env.DB_PORT || (cloudMode ? 4000 : 3306)
    ),

    user: process.env.DB_USER || (cloudMode ? "" : "root"),
    password: process.env.DB_PASSWORD || "",
    database: process.env.DB_NAME || "enterprise_attendance",

    waitForConnections: true,
    connectionLimit: 10,

    ...(cloudMode && {
        ssl: {
            minVersion: "TLSv1.2",
            rejectUnauthorized: true,
        },
    }),
});

if (cloudMode &&
    (!process.env.DB_HOST ||
        !process.env.DB_USER ||
        !process.env.DB_PASSWORD)) {
    throw new Error("Missing required TiDB Cloud credentials.");
}

module.exports = db.promise();

// dDb3AJuPw4pJt94N