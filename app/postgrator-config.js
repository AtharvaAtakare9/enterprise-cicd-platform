require("dotenv").config();
const path = require("path");

const connectionString =
  process.env.NODE_ENV === "test"
    ? process.env.TEST_DATABASE_URL
    : process.env.DATABASE_URL;

module.exports = {
  migrationPattern: path.join(__dirname, "migrations", "*.sql"),
  driver: "pg",
  connectionString,
  password: "postgres"
};