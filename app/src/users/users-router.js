const UsersService = require("./users-service");
const path = require("path");
const express = require("express");
const xss = require('xss')
const { requireAuth } = require('../middleware/jwt-auth')

const usersRouter = express.Router();
const jsonParser = express.json();

const serializeUser = user => ({
    id: user.id,
    full_name: xss(user.full_name),
    username: xss(user.username),
    email_address: xss(user.email_address),
    date_created: new Date(user.date_created)
})

usersRouter
    .route('/')
    .get((req, res, next) => {
        const knexInstance = req.app.get('db')
        UsersService.getAllUsers(knexInstance)
            .then(users => {
                res.json(users.map(serializeUser))
            })
            .catch(next)
    })
    .post(jsonParser, (req, res, next) => {
        const { password, username, full_name, email_address } = req.body;
        for (const field of ['full_name', 'username', 'password', 'email_address']) {
            if (!req.body[field]) {
                return res.status(400).json({
                    error: `Missing '${field}' in request body`
                });
            }
        }
        const passwordError = UsersService.validatePassword(password)

        if (passwordError) {
            return res.status(400).json({ error: passwordError })
        }
        UsersService.hasUserWithUserName(req.app.get('db'), username)
            .then(hasUserWithUserName => {
                if (hasUserWithUserName) {
                    return res.status(400).json({ error: 'Username already taken' })
                }
                return UsersService.hashPassword(password).then(hashedPassword => {
                    const newUser = {
                        username,
                        password: hashedPassword,
                        full_name,
                        email_address,
                        date_created: "now()"
                    }
                    return UsersService.insertUser(req.app.get('db'), newUser).then(
                        user => {
                            res.status(201)
                                .location(path.posix.join(req.originalUrl, `/${user.id}`))
                                .json(serializeUser(user))
                        }
                    )
                });
            })
            .catch(next)
    })

{/* //For future use
usersRouter
    .route("/:user_id")
    .all(requireAuth)
    .get((req, res) => {
        res.json(serializeUser(req.user));
    })
    .delete((req, res, next) => {
        UsersService.deleteUser(req.app.get("db"), req.params.user_id)
            .then(numRowsAffected => {
                res.status(204).end();
            })
            .catch(next);
    })
    .patch(jsonParser, (req, res, next) => {
        const { full_name, email_address, password } = req.body;
        const userToUpdate = { full_name, email_address, password };
        const numberOfValues = Object.values(userToUpdate).filter(Boolean)
            .length;
        if (numberOfValues === 0) {
            return res.status(400).json({
                error: `Request body must contain either 'full name', 'email address', or 'password'`
            });
        }
        UsersService.updateUser(
            req.app.get("db"),
            req.params.user_id,
            userToUpdate
        )
            .then(numRowsAffected => {
                res.status(204).end();
            })
            .catch(next);
    });
*/}
module.exports = usersRouter