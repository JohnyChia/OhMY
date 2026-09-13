function recommendationReply(result, language = 'en') {
  if (!result || result.success === false || !Array.isArray(result.recommendations)
      || !result.recommendations.length) return null;
  return language === 'ms' ? 'Cadangan tersedia. Pilih tempat pada kad Nova.'
    : language === 'zh-CN' ? '推荐已准备好。请在 Nova 卡片中选择地点。'
      : 'Recommendations are ready. Select a place from the Nova cards.';
}
module.exports = { recommendationReply };
