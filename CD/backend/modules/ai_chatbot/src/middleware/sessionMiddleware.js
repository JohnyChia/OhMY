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



if (process.env.NODE_ENV !== "production") {
  console.info("[Nova session] ready=true");
}



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
