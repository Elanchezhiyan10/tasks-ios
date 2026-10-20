require("dotenv").config();
const {
    authenticateToken,
    requireHR
} = require("./middleware/auth");
const express = require("express");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const db = require("./db");
const path = require("path");

const app = express();

const cors = require("cors");

app.use(cors({
    origin: (origin, callback) => {
        // Allow requests without an Origin header (e.g. API tools)
        if (!origin) {
            return callback(null, true);
        }

        try {
            const url = new URL(origin);

            if (
                ["localhost", "127.0.0.1"].includes(url.hostname) &&
                ["http:", "https:"].includes(url.protocol)
            ) {
                return callback(null, true);
            }
        } catch (_) {
            // Invalid origin
        }

        return callback(new Error("Origin not allowed"));
    },
    methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization"]
}));

app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

// Validate JWT configuration
if (!process.env.JWT_SECRET ||
    process.env.JWT_SECRET.length < 32) {
    throw new Error("JWT_SECRET must be at least 32 characters.");
}

// Home route
app.get("/", (req, res) => {
    res.json({
        message: "Enterprise Attendance API is running"
    });
});

// Database health check
app.get("/health/db", async (req, res) => {
    try {
        const [rows] = await db.query(
            "SELECT DATABASE() AS database_name"
        );

        res.json({
            connected: true,
            database: rows[0].database_name
        });
    } catch (error) {
        console.error(error.message);

        res.status(500).json({
            connected: false,
            message: "Database connection failed"
        });
    }
});

app.post("/auth/register", async (req, res) => {
    try {
        const {
            employee_code,
            full_name,
            email,
            password
        } = req.body || {};

        if (
            typeof employee_code !== "string" ||
            typeof full_name !== "string" ||
            typeof email !== "string" ||
            typeof password !== "string"
        ) {
            return res.status(400).json({
                message: "All fields are required."
            });
        }

        const code = employee_code.trim().toUpperCase();
        const name = full_name.trim();
        const normalizedEmail = email.trim().toLowerCase();

        if (
            !code ||
            !name ||
            name.length > 100 ||
            code.length > 30 ||
            normalizedEmail.length > 150 ||
            !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)
        ) {
            return res.status(400).json({
                message: "Enter valid employee details."
            });
        }

        if (
            password.length < 12 ||
            Buffer.byteLength(password, "utf8") > 72
        ) {
            return res.status(400).json({
                message: "Password must be at least 12 characters and no more than 72 UTF-8 bytes."
            });
        }

        const passwordHash = await bcrypt.hash(password, 12);

        await db.query(
            `INSERT INTO users
             (employee_code, full_name, email, password_hash, role)
             VALUES (?, ?, ?, ?, 'employee')`,
            [code, name, normalizedEmail, passwordHash]
        );

        return res.status(201).json({
            message: "Employee registered successfully. You can now log in."
        });
    } catch (error) {
        if (error.code === "ER_DUP_ENTRY") {
            return res.status(409).json({
                message: "Employee code or email already exists."
            });
        }

        console.error("Registration error:", error.message);

        return res.status(500).json({
            message: "Unable to register employee."
        });
    }
});

// Login route
app.post("/auth/login", async (req, res) => {
    try {
        const { email, password } = req.body || {};

        if (
            typeof email !== "string" ||
            typeof password !== "string" ||
            !email.trim() ||
            !password ||
            email.length > 150 ||
            password.length > 128
        ) {
            return res.status(400).json({
                message: "Enter a valid email and password."
            });
        }

        const [users] = await db.query(
            `SELECT id, employee_code, full_name,
                    email, password_hash, role, is_active
             FROM users
             WHERE email = ?
             LIMIT 1`,
            [email.trim()]
        );

        if (users.length === 0) {
            return res.status(401).json({
                message: "Invalid email or password."
            });
        }

        const user = users[0];

        const passwordMatches = await bcrypt.compare(
            password,
            user.password_hash
        );

        if (!passwordMatches || !user.is_active) {
            return res.status(401).json({
                message: "Invalid email or password."
            });
        }

        const token = jwt.sign(
            {
                sub: String(user.id),
                role: user.role
            },
            process.env.JWT_SECRET,
            {
                expiresIn: "8h",
                algorithm: "HS256"
            }
        );

        return res.json({
            message: "Login successful",
            token,
            user: {
                id: user.id,
                employee_code: user.employee_code,
                full_name: user.full_name,
                email: user.email,
                role: user.role
            }
        });
    } catch (error) {
        console.error("Login error:", error.message);

        return res.status(500).json({
            message: "Unable to process login."
        });
    }
});

// Start server


app.get("/auth/me", authenticateToken, (req, res) => {
    res.json({
        message: "Authentication successful",
        user: req.user
    });
});

app.get(
    "/hr/test",
    authenticateToken,
    requireHR,
    (req, res) => {
        res.json({
            message: "HR access granted"
        });
    }
);

app.post("/attendance/check-in", authenticateToken, async (req, res) => {
    try {
        if (req.user.role !== "employee") {
            return res.status(403).json({
                message: "Only employees can check in."
            });
        }

        const userId = req.user.id;

        const [result] = await db.query(
            `INSERT INTO attendance
             (user_id, attendance_date, check_in_at)
             VALUES (?, CURDATE(), NOW())`,
            [userId]
        );

        return res.status(201).json({
            message: "Check-in successful",
            attendance_id: result.insertId
        });

    } catch (error) {
        if (error.code === "ER_DUP_ENTRY") {
            return res.status(409).json({
                message: "Attendance already exists for today."
            });
        }

        console.error("Check-in error:", error.message);

        return res.status(500).json({
            message: "Unable to check in."
        });
    }
});

app.post("/attendance/check-out", authenticateToken, async (req, res) => {
    try {
        if (req.user.role !== "employee") {
            return res.status(403).json({
                message: "Only employees can check out."
            });
        }

        const [result] = await db.query(
            `UPDATE attendance
             SET check_out_at = NOW()
             WHERE user_id = ?
               AND attendance_date = CURDATE()
               AND check_in_at IS NOT NULL
               AND check_out_at IS NULL`,
            [req.user.id]
        );

        if (result.affectedRows === 0) {
            return res.status(409).json({
                message: "No active check-in found for today."
            });
        }

        res.json({
            message: "Check-out successful"
        });
    } catch (error) {
        console.error("Check-out error:", error.message);

        res.status(500).json({
            message: "Unable to check out."
        });
    }
});


// Get current week's attendance
app.get(
    "/attendance/weekly",
    authenticateToken,
    async (req, res) => {
        try {
            const userId = req.user.id;

            const sql = `
                SELECT
                    id,
                    user_id,
                    DATE_FORMAT(attendance_date, '%Y-%m-%d')
                        AS attendance_date,
                    check_in_at,
                    check_out_at
                FROM attendance
                WHERE user_id = ?
                  AND attendance_date >=
                      DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY)
                  AND attendance_date <= CURDATE()
                ORDER BY attendance_date DESC
            `;

            const [rows] = await db.query(sql, [userId]);

            res.status(200).json({
                attendance: rows
            });

        } catch (error) {
            console.error("Weekly attendance error:", error);

            res.status(500).json({
                message: "Failed to load weekly attendance."
            });
        }
    }
);


/* =========================
   TASK MANAGEMENT APIs
   ========================= */

// Create a task
app.post("/tasks", authenticateToken, async (req, res) => {
    try {
        const {
            title,
            description = null,
            priority = "medium",
            scheduled_at,
            reminder_at = null,
            recurrence = null
        } = req.body;

        if (!title || !title.trim() || !scheduled_at) {
            return res.status(400).json({
                message: "Task title and scheduled time are required."
            });
        }

        if (!["low", "medium", "high"].includes(priority)) {
            return res.status(400).json({
                message: "Priority must be low, medium, or high."
            });
        }

        const parseLocalDateTime = (value) => {
            if (typeof value !== "string") return null;

            // Accept: YYYY-MM-DD HH:mm:ss or YYYY-MM-DDTHH:mm:ss
            const match = value.match(
                /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$/
            );

            if (!match) return null;

            const [, y, mo, d, h, mi, s = "00"] = match;
            const parts = [y, mo, d, h, mi, s].map(Number);

            const [year, month, day, hour, minute, second] = parts;
            const date = new Date(year, month - 1, day, hour, minute, second);

            // Reject invalid dates and times instead of silently normalizing them.
            if (
                date.getFullYear() !== year ||
                date.getMonth() !== month - 1 ||
                date.getDate() !== day ||
                date.getHours() !== hour ||
                date.getMinutes() !== minute ||
                date.getSeconds() !== second
            ) {
                return null;
            }

            return {
                date,
                mysql: `${y}-${mo}-${d} ${h}:${mi}:${s}`,
                dateOnly: `${y}-${mo}-${d}`
            };
        };

        const scheduled = parseLocalDateTime(scheduled_at);

        if (!scheduled) {
            return res.status(400).json({
                message: "Invalid scheduled time. Use YYYY-MM-DD HH:mm:ss."
            });
        }

        const scheduledDate = scheduled.date;
        const scheduledMySQL = scheduled.mysql;

        const connection = await db.getConnection();

        try {
            await connection.beginTransaction();

            const [taskResult] = await connection.execute(
                `INSERT INTO tasks
                    (user_id, title, description, priority, timezone)
                 VALUES (?, ?, ?, ?, ?)`,
                [
                    req.user.id,
                    title.trim(),
                    description,
                    priority,
                    "Asia/Kolkata"
                ]
            );

            const taskId = taskResult.insertId;

            const [occurrenceResult] = await connection.execute(
                `INSERT INTO task_occurrences
                    (task_id, scheduled_at)
                 VALUES (?, ?)`,
                [taskId, scheduledMySQL]
            );

            const occurrenceId = occurrenceResult.insertId;

            if (reminder_at) {
                const reminder = parseLocalDateTime(reminder_at);

                if (!reminder) {
                    throw new Error("Invalid reminder time.");
                }

                const reminderDate = reminder.date;

                if (
                    Number.isNaN(reminderDate.getTime()) ||
                    reminderDate >= scheduledDate
                ) {
                    throw new Error(
                        "Reminder time must be valid and before the task time."
                    );
                }

                await connection.execute(
                    `INSERT INTO task_reminders
                        (occurrence_id, remind_at)
                     VALUES (?, ?)`,
                    [occurrenceId, reminder.mysql]
                );
            }

            if (recurrence) {
                const allowedFrequencies = [
                    "daily",
                    "weekly",
                    "custom"
                ];

                if (
                    !allowedFrequencies.includes(recurrence.frequency) ||
                    !Number.isInteger(recurrence.interval_value) ||
                    recurrence.interval_value < 1
                ) {
                    throw new Error("Invalid recurrence settings.");
                }

                const startDate = scheduled.dateOnly;

                await connection.execute(
                    `INSERT INTO task_recurrence
                        (task_id, frequency, interval_value,
                         days_of_week, start_date, end_date, timezone)
                     VALUES (?, ?, ?, ?, ?, ?, ?)`,
                    [
                        taskId,
                        recurrence.frequency,
                        recurrence.interval_value,
                        recurrence.days_of_week
                            ? JSON.stringify(recurrence.days_of_week)
                            : null,
                        startDate,
                        recurrence.end_date || null,
                        "Asia/Kolkata"
                    ]
                );
            }

            await connection.commit();

            return res.status(201).json({
                message: "Task created successfully.",
                task_id: taskId,
                occurrence_id: occurrenceId
            });
        } catch (error) {
            await connection.rollback();
            throw error;
        } finally {
            connection.release();
        }
    } catch (error) {
        console.error("Create task error:", error);

        return res.status(500).json({
            message: "Unable to create task."
        });
    }
});


app.patch("/tasks/:id", authenticateToken, async (req, res) => {
    let connection;

    try {
        const taskId = Number(req.params.id);
        const {
            occurrence_id,
            title,
            description = null,
            priority = "medium",
            scheduled_at,
            reminder_at = null,
        } = req.body;

        const occurrenceId = Number(occurrence_id);

        if (
            !Number.isSafeInteger(taskId) ||
            taskId <= 0 ||
            !Number.isSafeInteger(occurrenceId) ||
            occurrenceId <= 0
        ) {
            return res.status(400).json({
                message: "Valid task and occurrence IDs are required.",
            });
        }

        if (
            typeof title !== "string" ||
            !title.trim() ||
            !scheduled_at
        ) {
            return res.status(400).json({
                message: "Task title and scheduled time are required.",
            });
        }

        if (!["low", "medium", "high"].includes(priority)) {
            return res.status(400).json({
                message: "Priority must be low, medium, or high.",
            });
        }

        // Parse local wall-clock time without converting it to UTC.
        const parseLocalDateTime = (value) => {
            if (typeof value !== "string") return null;

            const match = value.match(
                /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$/
            );

            if (!match) return null;

            const [, y, mo, d, h, mi, s = "00"] = match;
            const [year, month, day, hour, minute, second] =
                [y, mo, d, h, mi, s].map(Number);

            const date = new Date(
                year, month - 1, day, hour, minute, second
            );

            if (
                date.getFullYear() !== year ||
                date.getMonth() !== month - 1 ||
                date.getDate() !== day ||
                date.getHours() !== hour ||
                date.getMinutes() !== minute ||
                date.getSeconds() !== second
            ) {
                return null;
            }

            return {
                date,
                mysql: `${y}-${mo}-${d} ${h}:${mi}:${s}`,
            };
        };

        const scheduled = parseLocalDateTime(scheduled_at);

        if (!scheduled) {
            return res.status(400).json({
                message: "Invalid scheduled time. Use YYYY-MM-DD HH:mm:ss.",
            });
        }

        let reminder = null;

        if (reminder_at != null && reminder_at !== "") {
            reminder = parseLocalDateTime(reminder_at);

            if (!reminder || reminder.date >= scheduled.date) {
                return res.status(400).json({
                    message: "Reminder must be valid and before the task time.",
                });
            }
        }

        connection = await db.getConnection();
        await connection.beginTransaction();

        // Confirm that this occurrence belongs to this user's task.
        const [rows] = await connection.execute(
            `SELECT o.id
       FROM task_occurrences o
       JOIN tasks t ON t.id = o.task_id
       WHERE t.id = ?
         AND o.id = ?
         AND t.user_id = ?
       FOR UPDATE`,
            [taskId, occurrenceId, req.user.id]
        );

        if (rows.length === 0) {
            await connection.rollback();

            return res.status(404).json({
                message: "Task or occurrence not found.",
            });
        }

        await connection.execute(
            `UPDATE tasks
       SET title = ?, description = ?, priority = ?
       WHERE id = ? AND user_id = ?`,
            [
                title.trim(),
                description,
                priority,
                taskId,
                req.user.id,
            ]
        );

        await connection.execute(
            `UPDATE task_occurrences
       SET scheduled_at = ?
       WHERE id = ? AND task_id = ?`,
            [scheduled.mysql, occurrenceId, taskId]
        );

        // Replace the reminder associated with this occurrence.
        await connection.execute(
            `DELETE FROM task_reminders WHERE occurrence_id = ?`,
            [occurrenceId]
        );

        if (reminder) {
            await connection.execute(
                `INSERT INTO task_reminders (occurrence_id, remind_at)
         VALUES (?, ?)`,
                [occurrenceId, reminder.mysql]
            );
        }

        await connection.commit();

        return res.json({
            message: "Task updated successfully.",
            task_id: taskId,
            occurrence_id: occurrenceId,
        });
    } catch (error) {
        if (connection) {
            try {
                await connection.rollback();
            } catch (rollbackError) {
                console.error("Edit task rollback error:", rollbackError);
            }
        }

        console.error("Update task error:", error);

        return res.status(500).json({
            message: "Unable to update task.",
        });
    } finally {
        connection?.release();
    }
});


// Get the logged-in employee's tasks
app.get("/tasks", authenticateToken, async (req, res) => {
    try {
        const { from, to } = req.query;
        await generateUpcomingOccurrences(req.user.id);

        let sql = `
    SELECT
        t.id AS task_id,
        t.title,
        t.description,
        t.priority,
        t.status AS task_status,
        o.id AS occurrence_id,
        DATE_FORMAT(o.scheduled_at, '%Y-%m-%d %H:%i:%s') AS scheduled_at,
        o.status AS occurrence_status,
        DATE_FORMAT(o.completed_at, '%Y-%m-%d %H:%i:%s') AS completed_at,
        DATE_FORMAT(r.remind_at, '%Y-%m-%d %H:%i:%s') AS remind_at
    FROM tasks t
    INNER JOIN task_occurrences o
        ON o.task_id = t.id
    LEFT JOIN task_reminders r
        ON r.occurrence_id = o.id
    WHERE t.user_id = ?
      AND t.status = 'active'
`;


        const params = [req.user.id];

        if (from) {
            sql += " AND o.scheduled_at >= ?";
            params.push(from.replace("T", " ").slice(0, 19));
        }

        if (to) {
            sql += " AND o.scheduled_at <= ?";
            params.push(to.replace("T", " ").slice(0, 19));
        }

        sql += " ORDER BY o.scheduled_at ASC";

        const [tasks] = await db.execute(sql, params);

        return res.json({ tasks });
    } catch (error) {
        console.error("Get tasks error:", error);

        return res.status(500).json({
            message: "Unable to fetch tasks."
        });
    }
});


async function generateUpcomingOccurrences(userId) {
    // Use the current date in India, regardless of the server's timezone.
    const indiaDate = new Intl.DateTimeFormat("en-CA", {
        timeZone: "Asia/Kolkata",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
    }).format(new Date());

    const toDate = (dateString) => {
        const [year, month, day] = dateString.split("-").map(Number);
        return new Date(Date.UTC(year, month - 1, day));
    };

    const formatDate = (date) => date.toISOString().slice(0, 10);

    const addDays = (dateString, days) => {
        const date = toDate(dateString);
        date.setUTCDate(date.getUTCDate() + days);
        return formatDate(date);
    };

    const dayDifference = (first, second) =>
        Math.round((toDate(second) - toDate(first)) / 86400000);

    const [rules] = await db.execute(
        `
    SELECT
        t.id AS task_id,
        DATE_FORMAT(r.start_date, '%Y-%m-%d') AS start_date,
        DATE_FORMAT(r.end_date, '%Y-%m-%d') AS end_date,
        r.frequency,
        r.interval_value,
        r.days_of_week,
        DATE_FORMAT(first_o.scheduled_at, '%H:%i:%s') AS task_time,
        DATE_FORMAT(first_o.scheduled_at, '%Y-%m-%d %H:%i:%s')
            AS original_scheduled_at,
        DATE_FORMAT(first_r.remind_at, '%Y-%m-%d %H:%i:%s')
            AS original_remind_at
    FROM task_recurrence r
    JOIN tasks t
        ON t.id = r.task_id
    JOIN (
        SELECT task_id, MIN(scheduled_at) AS first_scheduled_at
        FROM task_occurrences
        GROUP BY task_id
    ) earliest
        ON earliest.task_id = t.id
    JOIN task_occurrences first_o
        ON first_o.task_id = earliest.task_id
        AND first_o.scheduled_at = earliest.first_scheduled_at
    LEFT JOIN task_reminders first_r
        ON first_r.occurrence_id = first_o.id
        AND first_r.is_enabled = 1
    WHERE t.user_id = ?
        AND t.status = 'active'
        AND r.frequency IN ('daily', 'weekly')
    `,
        [userId]
    );

    const today = indiaDate;
    const horizon = addDays(today, 7);

    for (const rule of rules) {
        const interval = Number(rule.interval_value);

        if (!Number.isInteger(interval) || interval < 1) {
            continue;
        }

        let weekdays = [];

        if (rule.frequency === "weekly") {
            try {
                weekdays =
                    typeof rule.days_of_week === "string"
                        ? JSON.parse(rule.days_of_week)
                        : rule.days_of_week;

                if (
                    !Array.isArray(weekdays) ||
                    weekdays.length === 0 ||
                    weekdays.some(
                        (day) =>
                            !Number.isInteger(day) ||
                            day < 1 ||
                            day > 7
                    )
                ) {
                    continue;
                }
            } catch {
                continue;
            }
        }

        // Keep the original task's wall-clock time.
        const originalTime = rule.task_time;
        const originalScheduled = rule.original_scheduled_at;
        const originalReminder = rule.original_remind_at;

        let reminderOffsetSeconds = null;

        if (originalReminder) {
            const scheduledMs = Date.parse(
                originalScheduled.replace(" ", "T") + "Z"
            );
            const reminderMs = Date.parse(
                originalReminder.replace(" ", "T") + "Z"
            );

            const offset = Math.round(
                (scheduledMs - reminderMs) / 1000
            );

            if (offset > 0) {
                reminderOffsetSeconds = offset;
            }
        }

        const firstDate =
            rule.start_date > today ? rule.start_date : today;

        for (
            let date = firstDate;
            date <= horizon;
            date = addDays(date, 1)
        ) {
            if (rule.end_date && date > rule.end_date) {
                break;
            }

            const daysSinceStart = dayDifference(rule.start_date, date);

            if (daysSinceStart < 0) {
                continue;
            }

            let shouldCreate = false;

            if (rule.frequency === "daily") {
                shouldCreate = daysSinceStart % interval === 0;
            } else if (rule.frequency === "weekly") {
                // ISO weekday: Monday = 1, Sunday = 7.
                const weekday = toDate(date).getUTCDay() || 7;

                const startWeekday =
                    toDate(rule.start_date).getUTCDay() || 7;

                const startMonday = addDays(
                    rule.start_date,
                    -(startWeekday - 1)
                );

                const currentMonday = addDays(
                    date,
                    -(weekday - 1)
                );

                const weeksSinceStart = Math.floor(
                    dayDifference(startMonday, currentMonday) / 7
                );

                shouldCreate =
                    weeksSinceStart >= 0 &&
                    weeksSinceStart % interval === 0 &&
                    weekdays.includes(weekday);
            }

            if (!shouldCreate) {
                continue;
            }

            const scheduledAt = `${date} ${originalTime}`;

            // Duplicate-safe because of uq_task_scheduled.
            await db.execute(
                `
                INSERT IGNORE INTO task_occurrences
                    (task_id, scheduled_at)
                VALUES (?, ?)
                `,
                [rule.task_id, scheduledAt]
            );

            // Find the occurrence whether it was just inserted or already existed.
            const [occurrences] = await db.execute(
                `
                SELECT id
                FROM task_occurrences
                WHERE task_id = ? AND scheduled_at = ?
                LIMIT 1
                `,
                [rule.task_id, scheduledAt]
            );

            if (
                occurrences.length > 0 &&
                reminderOffsetSeconds !== null
            ) {
                const occurrenceId = occurrences[0].id;

                // Calculate the reminder using wall-clock components.
                const scheduledDate = toDate(date);
                const [hour, minute, second] = originalTime
                    .split(":")
                    .map(Number);

                scheduledDate.setUTCHours(hour, minute, second, 0);
                scheduledDate.setTime(
                    scheduledDate.getTime() -
                    reminderOffsetSeconds * 1000
                );

                const reminderAt =
                    `${formatDate(scheduledDate)} ` +
                    `${String(scheduledDate.getUTCHours()).padStart(2, "0")}:` +
                    `${String(scheduledDate.getUTCMinutes()).padStart(2, "0")}:` +
                    `${String(scheduledDate.getUTCSeconds()).padStart(2, "0")}`;

                await db.execute(
                    `
                    INSERT IGNORE INTO task_reminders
                        (occurrence_id, remind_at, is_enabled)
                    VALUES (?, ?, 1)
                    `,
                    [occurrenceId, reminderAt]
                );
            }
        }
    }
}


// Mark a task occurrence as completed
app.patch(
    "/tasks/occurrences/:id/complete",
    authenticateToken,
    async (req, res) => {
        try {
            const [result] = await db.execute(
                `UPDATE task_occurrences o
                 INNER JOIN tasks t ON t.id = o.task_id
                 SET o.status = 'completed',
                     o.completed_at = NOW()
                 WHERE o.id = ?
                   AND t.user_id = ?
                   AND t.status = 'active'
                   AND o.status = 'pending'`,
                [req.params.id, req.user.id]
            );

            if (result.affectedRows === 0) {
                return res.status(404).json({
                    message: "Task not found or already completed."
                });
            }

            return res.json({
                message: "Task marked as completed."
            });
        } catch (error) {
            console.error("Complete task error:", error);

            return res.status(500).json({
                message: "Unable to complete task."
            });
        }
    }
);


// Reopen a completed task occurrence
app.patch(
    "/tasks/occurrences/:id/reopen",
    authenticateToken,
    async (req, res) => {
        try {
            const [result] = await db.execute(
                `UPDATE task_occurrences o
                 INNER JOIN tasks t ON t.id = o.task_id
                 SET o.status = 'pending',
                     o.completed_at = NULL
                 WHERE o.id = ?
                   AND t.user_id = ?
                   AND t.status = 'active'
                   AND o.status = 'completed'`,
                [req.params.id, req.user.id]
            );

            if (result.affectedRows === 0) {
                return res.status(404).json({
                    message: "Completed task not found."
                });
            }

            return res.json({
                message: "Task reopened."
            });
        } catch (error) {
            console.error("Reopen task error:", error);

            return res.status(500).json({
                message: "Unable to reopen task."
            });
        }
    }
);


// Delete a task belonging to the logged-in employee
app.delete("/tasks/:id", authenticateToken, async (req, res) => {
    try {
        const [result] = await db.execute(
            `DELETE FROM tasks
             WHERE id = ? AND user_id = ?`,
            [req.params.id, req.user.id]
        );

        if (result.affectedRows === 0) {
            return res.status(404).json({
                message: "Task not found."
            });
        }

        return res.json({
            message: "Task deleted successfully."
        });
    } catch (error) {
        console.error("Delete task error:", error);

        return res.status(500).json({
            message: "Unable to delete task."
        });
    }
});


const PORT = process.env.PORT || 3000;

app.listen(PORT, "0.0.0.0", () => {
    console.log(`Server running on port ${PORT}`);
});