const express = require('express');
const multer = require('multer');
const fs = require('fs');
const { analyzeAttachment, MAX_FILE_BYTES } = require('../services/attachmentAnalysisService');
const requireNovaUser = require('../middleware/requireNovaUser');
const supabase = require('../config/supabase');

const router = express.Router();
const upload = multer({ dest: 'uploads/attachments/', limits: { fileSize: MAX_FILE_BYTES, files: 1 } });

router.post('/analyze-attachment', requireNovaUser, upload.single('attachment'), async (req, res) => {
  const cleanup = () => { if (req.file?.path) fs.unlink(req.file.path, () => {}); };
  try {
    if (!req.file) return res.status(400).json({ success: false, error: 'No attachment provided.' });
    const analysis = await analyzeAttachment(req.file);
    cleanup();
    return res.json({ success: true, analysis });
  } catch (error) {
    cleanup();
    return res.status(400).json({ success: false, error: error.message || 'Attachment analysis failed.' });
  }
});

router.post('/save-travel-item-binary', requireNovaUser, upload.single('attachment'), async (req, res) => {
  const cleanup = () => { if (req.file?.path) fs.unlink(req.file.path, () => {}); };
  try {
    if (!req.file) return res.status(400).json({ success: false, error: 'No attachment provided.' });
    const itemId = String(req.body.item_id || '').trim();
    if (!/^[0-9a-f-]{36}$/i.test(itemId)) {
      cleanup();
      return res.status(400).json({ success: false, error: 'A valid saved item id is required.' });
    }
    await analyzeAttachment(req.file);
    const { data: ownedItem, error: ownershipError } = await supabase
      .from('saved_travel_items')
      .select('id')
      .eq('id', itemId)
      .eq('user_id', req.novaUserId)
      .maybeSingle();
    if (ownershipError) throw ownershipError;
    if (!ownedItem) {
      cleanup();
      return res.status(404).json({ success: false, error: 'The saved travel item was not found.' });
    }
    const safeName = String(req.file.originalname || 'attachment')
      .replace(/[^A-Za-z0-9._-]/g, '_')
      .slice(-160);
    const storagePath = `${req.novaUserId}/${itemId}/${safeName}`;
    const bytes = fs.readFileSync(req.file.path);
    const { error: uploadError } = await supabase.storage
      .from('saved-travel-items')
      .upload(storagePath, bytes, {
        contentType: req.file.mimetype || 'application/octet-stream',
        upsert: true,
      });
    if (uploadError) throw uploadError;
    const { error: updateError } = await supabase
      .from('saved_travel_items')
      .update({
        storage_path: storagePath,
        updated_at: new Date().toISOString(),
      })
      .eq('id', itemId)
      .eq('user_id', req.novaUserId);
    if (updateError) throw updateError;
    cleanup();
    return res.json({ success: true, item_id: itemId, storage_path: storagePath });
  } catch (error) {
    cleanup();
    return res.status(400).json({ success: false, error: error.message || 'The travel item could not be saved.' });
  }
});

module.exports = router;
