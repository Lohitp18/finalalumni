const express = require("express");
const cors = require("cors");
const dotenv = require("dotenv");
const connectDB = require("./config/db");

dotenv.config();

const app = express();
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use('/uploads', express.static('uploads'));

connectDB();

app.get("/api/health", (_req, res) => res.json({ status: "ok" }));

// Test endpoint to verify database connection
app.get("/api/test-db", async (_req, res) => {
  try {
    const User = require("./models/User");
    const count = await User.countDocuments();
    res.json({ status: "ok", message: "Database connected", userCount: count });
  } catch (error) {
    res.status(500).json({ status: "error", message: "Database connection failed", error: error.message });
  }
});
app.use("/api/auth", require("./routes/authRoutes"));
app.use("/api/content", require("./routes/contentRoutes"));
app.use("/api/users", require("./routes/userRoutes"));
app.use("/api/admin", require("./routes/adminRoutes"));
app.use("/api/connections", require("./routes/connectionRoutes"));
app.use("/api/posts", require("./routes/postRoutes"));
app.use("/api/notifications", require("./routes/notificationRoutes"));
app.use("/api/reports", require("./routes/reportRoutes"));

// Minimal web admin UI (no auth) for reviewing pending items
app.get('/admin', (_req, res) => {
  res.send(`<!doctype html>
  <html>
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>Admin Dashboard</title>
      <style>
        body { font-family: Arial, sans-serif; margin: 24px; }
        a { display: inline-block; margin-right: 16px; }
      </style>
    </head>
    <body>
      <h1>Admin Dashboard</h1>
      <nav>
        <a href="/admin/pending-events">Pending Events</a>
        <a href="/admin/pending-opportunities">Pending Opportunities</a>
      </nav>
    </body>
  </html>`);
});
app.get('/admin/pending-events', (_req, res) => {
    res.type('html').send(`<!doctype html>
    <html>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Pending Events</title>
        <style>
          body { font-family: Arial, sans-serif; margin: 24px; }
          .card { border: 1px solid #ddd; border-radius: 8px; padding: 12px; margin-bottom: 12px; }
          button { margin-right: 8px; cursor: pointer; }
        </style>
      </head>
      <body>
        <h2>Pending Events</h2>
        <div id="list">Loading...</div>
        <script>
          async function load() {
            try {
              const res = await fetch('/api/content/admin/pending-events');
              const items = await res.json();
              const list = document.getElementById('list');
  
              if (!Array.isArray(items) || items.length === 0) {
                list.textContent = 'No pending events.';
                return;
              }
  
              list.innerHTML = items.map(e => {
                const title = e.title ? e.title : '';
                const desc = e.description ? e.description : (e.content || '');
                return \`
                  <div class="card">
                    <h3>\${title}</h3>
                    <p>\${desc}</p>
                    <div>
                      <button onclick="act('\${e._id}','approved')">Approve</button>
                      <button onclick="act('\${e._id}','rejected')">Reject</button>
                    </div>
                  </div>
                \`;
              }).join('');
            } catch (err) {
              document.getElementById('list').textContent = 'Error loading events.';
              console.error(err);
            }
          }
  
          async function act(id, status) {
            try {
              await fetch('/api/content/admin/events/' + id + '/status', {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ status })
              });
              load();
            } catch (err) {
              alert('Action failed.');
              console.error(err);
            }
          }
  
          load();
        </script>
      </body>
    </html>`);
  });
  
  app.get('/admin/pending-opportunities', (_req, res) => {
    res.type('html').send(`<!doctype html>
    <html>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Pending Opportunities</title>
        <style>
          body { font-family: Arial, sans-serif; margin: 24px; }
          .card { border: 1px solid #ddd; border-radius: 8px; padding: 12px; margin-bottom: 12px; }
          button { margin-right: 8px; cursor: pointer; }
        </style>
      </head>
      <body>
        <h2>Pending Opportunities</h2>
        <div id="list">Loading...</div>
        <script>
          async function load() {
            try {
              const res = await fetch('/api/content/admin/pending-opportunities');
              const items = await res.json();
              const list = document.getElementById('list');
  
              if (!Array.isArray(items) || items.length === 0) {
                list.textContent = 'No pending opportunities.';
                return;
              }
  
              list.innerHTML = items.map(e => {
                const title = e.title ? e.title : '';
                const company = e.company ? e.company : '';
                const desc = e.description ? e.description : '';
                return \`
                  <div class="card">
                    <h3>\${title}</h3>
                    <p><strong>Company:</strong> \${company}</p>
                    <p>\${desc}</p>
                    <div>
                      <button onclick="act('\${e._id}','approved')">Approve</button>
                      <button onclick="act('\${e._id}','rejected')">Reject</button>
                    </div>
                  </div>
                \`;
              }).join('');
            } catch (err) {
              document.getElementById('list').textContent = 'Error loading opportunities.';
              console.error(err);
            }
          }
  
          async function act(id, status) {
            try {
              await fetch('/api/content/admin/opportunities/' + id + '/status', {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ status })
              });
              load();
            } catch (err) {
              alert('Action failed.');
              console.error(err);
            }
          }
  
          load();
        </script>
      </body>
    </html>`);
  });

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(err.status || 500).json({
    message: err.message || 'Internal server error',
    error: process.env.NODE_ENV === 'development' ? err : {}
  });
});

// 404 handler for API routes
app.use('/api/*', (req, res) => {
  res.status(404).json({ message: 'API endpoint not found' });
});

const PORT = process.env.PORT || 5000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
