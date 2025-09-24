const express = require("express");
const {
  getApprovedAlumni,
  getProfile,
  updateProfile,
  updatePrivacySettings,
  changePassword,
  getUserById,
  handleImageUpload,
  uploadProfileImage,
  uploadCoverImage,
} = require("../controllers/userController");
const authMiddleware = require("../middlewares/authMiddleware");

const router = express.Router();


// ✅ Order matters! Put static routes BEFORE dynamic ones.

// Public routes
router.get("/approved", getApprovedAlumni);


router.get("/profile", authMiddleware, getProfile);
router.put("/profile", authMiddleware, updateProfile);
router.put("/privacy-settings", authMiddleware, updatePrivacySettings);
router.put("/change-password", authMiddleware, changePassword);
router.put("/profile-image", authMiddleware, handleImageUpload, uploadProfileImage);
router.put("/cover-image", authMiddleware, handleImageUpload, uploadCoverImage);

// Public routes
router.get("/approved", getApprovedAlumni);
router.get("/:id", getUserById); // Get user profile by ID (public, but respects privacy settings)

// Dynamic route must come last
router.get("/:id", getUserById); // Get user profile by ID (public, but respects privacy settings)

module.exports = router;
