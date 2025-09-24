const User = require("../models/User");

const mongoose = require("mongoose");

const bcrypt = require('bcryptjs');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

// GET /api/users/approved?year=&institution=&course=&q=
exports.getApprovedAlumni = async (req, res) => {
  try {
    const { year, institution, course, q } = req.query;
    const filter = { status: "approved" };

    if (year) filter.year = year;
    if (institution) filter.institution = { $regex: institution, $options: "i" };
    if (course) filter.course = { $regex: course, $options: "i" };

    // Text search on name or email if q provided
    if (q) {
      filter.$or = [
        { name: { $regex: q, $options: "i" } },
        { email: { $regex: q, $options: "i" } },
      ];
    }

    const users = await User.find(filter)
      .select("name email phone institution course year createdAt")
      .sort({ createdAt: -1 })
      .limit(200);

    return res.json(users);
  } catch (err) {
    console.error("getApprovedAlumni error", err);
    return res.status(500).json({ message: "Failed to fetch alumni" });
  }
};

// GET /api/users/profile - Get current user's profile
exports.getProfile = async (req, res) => {
  try {
    const user = await User.findById(req.user._id).select("-password");
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }
    res.json(user);
  } catch (error) {
    console.error("Error fetching profile:", error);
    res.status(500).json({ message: "Server error" });
  }
};

// PUT /api/users/profile - Update current user's profile
exports.updateProfile = async (req, res) => {
  try {
    const userId = req.user._id;
    const updateData = req.body;

    // Remove fields that shouldn't be updated directly
    delete updateData.password;
    delete updateData._id;
    delete updateData.email; // Email shouldn't be changed via profile update
    delete updateData.status;
    delete updateData.isAdmin;

    const user = await User.findByIdAndUpdate(userId, updateData, {
      new: true,
      runValidators: true,
    }).select("-password");

    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    res.json(user);
  } catch (error) {
    console.error("Error updating profile:", error);
    res.status(500).json({ message: "Server error" });
  }
};

// PUT /api/users/privacy-settings - Update privacy settings
exports.updatePrivacySettings = async (req, res) => {
  try {
    const userId = req.user._id;
    const privacySettings = req.body;

    const user = await User.findByIdAndUpdate(
      userId,
      { privacySettings },
      { new: true, runValidators: true }
    ).select("-password");

    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    res.json({
      message: "Privacy settings updated successfully",
      privacySettings: user.privacySettings,
    });
  } catch (error) {
    console.error("Error updating privacy settings:", error);
    res.status(500).json({ message: "Server error" });
  }
};

// GET /api/users/:id - Get user profile by ID
exports.getUserById = async (req, res) => {
  try {
    const { id } = req.params;

    // Prevent CastError for non-ObjectId values like "profile"
    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ message: "Invalid user ID" });
    }

    const user = await User.findById(id).select("-password");

    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    // Check privacy settings
    if (user.privacySettings?.profileVisibility === "private") {
      return res.status(403).json({ message: "Profile is private" });
    }

    res.json(user);
  } catch (error) {
    console.error("Error fetching user profile:", error);
    res.status(500).json({ message: "Server error" });
  }
};

// PUT /api/users/change-password - Change password
exports.changePassword = async (req, res) => {
  try {
    const { currentPassword, newPassword } = req.body;
    const userId = req.user._id;

    if (!currentPassword || !newPassword) {
      return res
        .status(400)
        .json({ message: "Current password and new password are required" });
    }

    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    // Verify current password
    const isMatch = await bcrypt.compare(currentPassword, user.password);
    if (!isMatch) {
      return res.status(400).json({ message: "Current password is incorrect" });
    }

    // Hash new password
    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash(newPassword, salt);

    user.password = hashedPassword;
    await user.save();

    res.json({ message: "Password changed successfully" });
  } catch (error) {
    console.error("Error changing password:", error);
    res.status(500).json({ message: "Server error" });
  }
};

// POST /api/auth/reset-password - Reset password by email (no auth)
exports.resetPasswordByEmail = async (req, res) => {
  try {
    const { email, newPassword } = req.body;
    if (!email || !newPassword) {
      return res
        .status(400)
        .json({ message: "Email and new password are required" });
    }

    const user = await User.findOne({ email });
    if (!user) {
      return res.status(404).json({ message: "Email not found" });
    }

    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash(newPassword, salt);
    user.password = hashedPassword;
    await user.save();

    return res.json({ message: "Password reset successfully" });
  } catch (error) {
    console.error("Error resetting password:", error);
    return res.status(500).json({ message: "Server error" });
  }
};


// ===== Image Uploads for Profile & Cover =====
const imageStorage = multer.diskStorage({
  destination: (_req, _file, cb) => {
    const uploadDir = 'uploads/';
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: (_req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
    cb(null, 'user-' + uniqueSuffix + path.extname(file.originalname));
  },
});

const imageUpload = multer({
  storage: imageStorage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (file.mimetype && file.mimetype.startsWith('image/')) return cb(null, true);
    return cb(new Error('Only image files are allowed'));
  }
}).single('image');

// Middleware wrapper to handle Multer errors cleanly
const handleImageUpload = (req, res, next) => {
  imageUpload(req, res, (err) => {
    if (err) {
      if (err.code === 'LIMIT_FILE_SIZE') {
        return res.status(400).json({ message: 'File too large. Max 5MB.' });
      }
      return res.status(400).json({ message: err.message || 'Upload failed' });
    }
    next();
  });
};

// PUT /api/users/profile-image
const uploadProfileImage = async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ message: 'No image uploaded' });
    const userId = req.user._id;
    const imageUrl = `/uploads/${req.file.filename}`;
    const user = await User.findByIdAndUpdate(
      userId,
      { profileImage: imageUrl },
      { new: true }
    ).select('-password');
    if (!user) return res.status(404).json({ message: 'User not found' });
    return res.json({ message: 'Profile image updated', user });
  } catch (error) {
    console.error('Error uploading profile image:', error);
    return res.status(500).json({ message: 'Server error' });
  }
};

// PUT /api/users/cover-image
const uploadCoverImage = async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ message: 'No image uploaded' });
    const userId = req.user._id;
    const imageUrl = `/uploads/${req.file.filename}`;
    const user = await User.findByIdAndUpdate(
      userId,
      { coverImage: imageUrl },
      { new: true }
    ).select('-password');
    if (!user) return res.status(404).json({ message: 'User not found' });
    return res.json({ message: 'Cover image updated', user });
  } catch (error) {
    console.error('Error uploading cover image:', error);
    return res.status(500).json({ message: 'Server error' });
  }
};

module.exports.handleImageUpload = handleImageUpload;
module.exports.uploadProfileImage = uploadProfileImage;
module.exports.uploadCoverImage = uploadCoverImage;


