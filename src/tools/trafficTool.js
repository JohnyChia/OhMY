async function get(params) {
  const location = params.destination || params.location || "City Center";
  return {
    location,
    status: "Moderate Traffic",
    estimatedDelay: "10-15 mins",
    recommendation: "Consider taking public transit or departure 15 minutes earlier."
  };
}

module.exports = {
  get
};
