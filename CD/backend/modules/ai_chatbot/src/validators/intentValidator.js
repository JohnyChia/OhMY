function normalizeDuration(value)
{

if(value===null || value===undefined)
{
return null;
}


if(typeof value==="number")
{
return value;
}



if(typeof value==="string")
{

const match=value.match(/\d+/);

if(match)
{
return Number(match[0]);
}



const text=value.toLowerCase();


if(text.includes("week"))
{
return 7;
}


if(text.includes("month"))
{
return 30;
}


}


return null;

}




function normalizeInterest(list)
{

if(!Array.isArray(list))
{
return [];
}



return list.map(item=>{

return String(item)
.toLowerCase()
.replace(
/(trip|tour|holiday|vacation)$/i,
""
)
.trim();


})
.filter(Boolean);


}






function validateIntent(data)
{


if(!data)
{

return {

intent:"general_chat",

confidence:0,

parameters:{}

};

}




data.intent =
data.intent ||
"general_chat";



data.confidence =
Number(data.confidence || 0);



data.action =
data.action || "";



data.tool =
data.tool || "";





data.parameters =
data.parameters || {};





data.parameters.duration =
normalizeDuration(
data.parameters.duration
);




data.parameters.interest =
normalizeInterest(
data.parameters.interest
);


if(
data.action==="remove_interest"
)
{

data.parameters.interest_action =
"remove_item";

}



if(
data.action==="add_interest"
)
{

data.parameters.interest_action =
"add_item";

}



if(
!Array.isArray(
data.parameters.interest_remove
)
)
{

data.parameters.interest_remove=[];

}





if(
!data.parameters.language
)
{

data.parameters.language="english";

}





if(
Array.isArray(data.missing_fields)
)
{


data.missing_fields =
data.missing_fields.filter(field=>{


if(field==="destination")
{
return !data.parameters.destination;
}


if(field==="duration")
{
return !data.parameters.duration;
}


if(field==="interest")
{
return data.parameters.interest.length===0;
}



return false;


});


}






if(data.intent!=="update_profile")
{

data.profile_update={

favorite_categories:[],
travel_style:"",
budget_preference:"",
preferred_language:""

};

}



return data;


}




module.exports={
validateIntent
};