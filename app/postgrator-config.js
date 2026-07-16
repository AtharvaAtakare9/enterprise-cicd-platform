require("dotenv").config();
const path = require("path");

module.exports = {
  migrationPattern: path.join(__dirname, "migrations", "*.sql"),
  driver: "pg",
  connectionString:
    process.env.NODE_ENV === "test"
      ? process.env.TEST_DATABASE_URL
      : process.env.DATABASE_URL,
};