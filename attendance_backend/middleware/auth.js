const jwt = require("jsonwebtoken");

function authenticateToken(req, res, next) {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith("Bearer ")) {
        return res.status(401).json({
            message: "Authentication token required."
        });
    }

    const token = authHeader.slice(7);

    try {
        const decoded = jwt.verify(
            token,
            process.env.JWT_SECRET,
            { algorithms: ["HS256"] }
        );

        if (
            !decoded.sub ||
            !["employee", "hr"].includes(decoded.role)
        ) {
            return res.status(403).json({
                message: "Invalid account permissions."
            });
        }

        req.user = {
            id: Number(decoded.sub),
            role: decoded.role
        };

        next();
    } catch (error) {
        return res.status(401).json({
            message: "Invalid or expired token."
        });
    }
}

function requireHR(req, res, next) {
    if (req.user?.role !== "hr") {
        return res.status(403).json({
            message: "HR access required."
        });
    }

    next();
}

module.exports = { authenticateToken, requireHR };