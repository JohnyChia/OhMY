const profileService =
require("../services/profileService");



async function update(
user_id,
data
){


return await profileService.updateProfile(
user_id,
{

favorite_categories:
data.favorite_categories || [],


travel_style:
data.travel_style || "",


budget_preference:
data.budget_preference || "",


preferred_language:
data.preferred_language || ""

}

);


}



module.exports={
update
};