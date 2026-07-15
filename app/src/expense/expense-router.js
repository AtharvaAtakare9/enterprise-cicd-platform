const path = require('path')
const xss = require('xss')
const express = require('express')
const ExpenseService = require('./expense-service')
const { requireAuth } = require('../middleware/jwt-auth')

const expenseRouter = express.Router()
const jsonParser = express.json()

const serializeExpense = expense => ({
    id: expense.id,
    expense: xss(expense.expense),
    user_id: expense.user_id,
    description: xss(expense.description),
    date_created: expense.date_created
});

expenseRouter
    .route('/')
    .all(requireAuth)
    .get((req, res, next) => {
        const knexInstance = req.app.get('db');
        ExpenseService.getUsersExpenses(knexInstance, req.user.id)
            .then((expense) => {
                
                res.json(expense.map(serializeExpense))
            })
            .catch(next)
    })
    .post(jsonParser, (req, res, next) => {
        const knexInstance = req.app.get('db')
        const { expense, description, user_id, date_created, id } = req.body;
        for (const field of ['expense']) {
            if (!req.body[field]) {
                return res.status(400).json({
                    error: `Missing '${field}' in request body`
                });
            }
        }
        const newExpense = {
            id,
            expense,
            description,
            user_id: req.user.id,
            date_created
        }
        ExpenseService.insertExpense(knexInstance, newExpense)
            .then(expense => {
                res.status(201)
                    .location(path.posix.join(req.originalUrl, `/${expense.id}`))
                    .json(serializeExpense(expense))
            })
            .catch(next)
    })

expenseRouter
    .route('/:expense_id')
    .all(requireAuth)
    .all((req, res, next) => {
        const knexInstance = req.app.get('db')
        ExpenseService.getUserExpenseById(knexInstance, req.params.expense_id, req.user.id)
            .then(expense => {
                if (!expense) {
                    return res.json({ error: `Expense doesn' exist`})
                }
                res.expense = expense
                next();
            })
            .catch(next)
    })
    .delete((req, res, next) => {
        ExpenseService
            .deleteExpense(req.app.get('db'), req.params.expense_id)
            .then(numRowsAffected => {
                res.status(204).end();
            })
            .catch(next)
    })
{/* for future use
    .get((req, res, next) => {
        res.json(serializeExpense(res.expense))
    })
    */}

module.exports = expenseRouter;