const knex = require("knex");
const bcrypt = require("bcryptjs");
const app = require("../src/app");
const helpers = require("./test-helpers");

describe("Users Endpoint", function () {
    let db;

    const { testUsers } = helpers.makeFixtures();
    const testUser = testUsers[0];

    before("make knex instance", () => {
        db = knex({
            client: "pg",
            connection: process.env.TEST_DATABASE_URL
        });
        app.set("db", db);
    });
    after("disconnect from db", () => db.destroy());

    before("cleanup", () => helpers.cleanTables(db));

    afterEach("cleanup", () => helpers.cleanTables(db));

    describe(`POST /api/users`, () => {
        context(`User validation`, () => {

            context("Happy path", () => {
                it("responds with 201, serialized user, storing bcrypted password", () => {
                    const newUser = {
                        full_name: "New Test User",
                        email_address: "newtestuser@thisemail.com",
                        username: "testusername1",
                        password: "GreatPassword14!"
                    };
                    return supertest(app)
                        .post("/api/users")
                        .send(newUser)
                        .expect(201)
                        .expect(res => {
                            expect(res.body).to.have.property("id");
                            expect(res.body.full_name).to.eql(
                                newUser.full_name
                            );
                            expect(res.body.email_address).to.eql(
                                newUser.email_address
                            );
                            expect(res.body.username).to.eql(newUser.username);
                            expect(res.body).to.not.have.property("password");
                            expect(res.headers.location).to.eql(
                                `/api/users/${res.body.id}`
                            );
                            const expectedDate = new Date().toLocaleString(
                                "en",
                                { timeZone: "UTC" }
                            );
                            const actualDate = new Date(
                                res.body.date_created
                            ).toLocaleString();
                            expect(actualDate).to.eql(expectedDate);
                        })
                        .expect(res => {
                            db.from("users")
                                .select("*")
                                .where({ id: res.body.id })
                                .first()
                                .then(row => {
                                    expect(row.username).to.eql(
                                        newUser.username
                                    );
                                    expect(row.full_name).to.eql(
                                        newUser.full_name
                                    );
                                    expect(row.email_address).to.eql(
                                        newUser.email_address
                                    );
                                    const expectedDate = new Date().toLocaleString(
                                        "en",
                                        { timeZone: "UTC" }
                                    );
                                    const actualDate = new Date(
                                        row.date_created
                                    ).toLocaleString();
                                    expect(actualDate).to.eql(expectedDate);
                                    return bcrypt.compare(
                                        newUser.password,
                                        row.password
                                    );
                                })
                                .then(compareMatch => {
                                    expect(compareMatch).to.be.true;
                                });
                        });
                });
            });
        });
    });
});
