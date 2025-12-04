const User = require("../models/User");
const bcrypt = require("bcryptjs");
const generateToken = require("../utils/generateToken");

// ✅ User Registration (Sign Up)
const registerUser = async (req, res) => {
  try {
    const { name, email, phone, dob, institution, course, year, password, favTeacher, socialMedia } = req.body;

    const userExists = await User.findOne({ email });
    if (userExists) return res.status(400).json({ message: "User already exists" });

    const hashedPassword = await bcrypt.hash(password, 10);

    // Parse date - handle both DD-MM-YYYY (from app) and YYYY-MM-DD (from web) formats
    let parsedDob = null;
    if (dob) {
      // Try parsing as ISO format (YYYY-MM-DD)
      parsedDob = new Date(dob);
      // If invalid, try DD-MM-YYYY format
      if (isNaN(parsedDob.getTime())) {
        const parts = dob.split('-');
        if (parts.length === 3) {
          // Assume DD-MM-YYYY format
          parsedDob = new Date(`${parts[2]}-${parts[1]}-${parts[0]}`);
        }
      }
      // If still invalid, set to null
      if (isNaN(parsedDob.getTime())) {
        parsedDob = null;
      }
    }

    const user = await User.create({
      name, email, phone, dob: parsedDob, institution, course, year,
      password: hashedPassword, favouriteTeacher: favTeacher || '', socialMedia: socialMedia || ''
    });

    res.status(201).json({
      _id: user._id,
      email: user.email,
      status: user.status,
      token: generateToken(user._id)
    });
  } catch (error) {
    res.status(500).json({ message: "Server error", error: error.message });
  }
};

// ✅ User Login (Sign In)
const loginUser = async (req, res) => {
  try {
    // Validate request body
    if (!req.body) {
      return res.status(400).json({ message: "Request body is required" });
    }

    const { email, password } = req.body;

    // Validate required fields
    if (!email || !password) {
      return res.status(400).json({ message: "Email and password are required" });
    }

    // Trim and validate email format
    const trimmedEmail = email.trim().toLowerCase();
    if (!trimmedEmail || trimmedEmail.length === 0) {
      return res.status(400).json({ message: "Email is required" });
    }

    if (!password || password.length === 0) {
      return res.status(400).json({ message: "Password is required" });
    }

    const user = await User.findOne({ email: trimmedEmail });
    if (!user) {
      return res.status(400).json({ message: "Invalid credentials" });
    }

    const isPasswordMatch = await bcrypt.compare(password, user.password);
    if (!isPasswordMatch) {
      return res.status(400).json({ message: "Invalid credentials" });
    }

    // Check if admin approved
    if (user.status !== "approved") {
      return res.status(403).json({ message: "Account not approved yet" });
    }

    res.json({
      _id: user._id,
      email: user.email,
      status: user.status,
      token: generateToken(user._id)
    });
  } catch (error) {
    console.error("Login error:", error);
    res.status(500).json({ message: "Server error", error: error.message });
  }
};

module.exports = { registerUser, loginUser };
