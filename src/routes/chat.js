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



router.post(

"/chat",

sessionMiddleware,

chatController

);



module.exports=router;