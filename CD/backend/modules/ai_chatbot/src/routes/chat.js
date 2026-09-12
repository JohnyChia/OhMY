const express=require("express");


const router=
express.Router();



const {
chatController
}
=
require("../controllers/chatController");



const sessionMiddleware=
require("../middleware/sessionMiddleware");
const requireNovaUser = require("../middleware/requireNovaUser");



router.post(

"/chat",

requireNovaUser,

sessionMiddleware,

chatController

);



module.exports=router;
