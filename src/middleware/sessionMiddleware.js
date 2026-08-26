const sessionService =
require("../services/sessionService");


async function sessionMiddleware(req,res,next)
{

try
{

const {
user_id
}
=
req.body;



console.log(
"SESSION USER:",
user_id
);



if(!user_id)
{

return res.status(400).json({

success:false,

error:"user_id required"

});

}



const session =
await sessionService.getOrCreateSession(
user_id
);



console.log(
"SESSION OBJECT:",
JSON.stringify(session,null,2)
);



req.session=session;


next();


}


catch(error)
{

console.error(
"SESSION MIDDLEWARE ERROR"
);

console.error(
error.stack
);


return res.status(500).json({

success:false,

error:error.message

});


}


}

module.exports=sessionMiddleware;