'use client'

export default function HomePage() {
  return (
    <div style={{
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      minHeight: '100vh',
      padding: '20px',
      textAlign: 'center'
    }}>
      <h1 style={{ fontSize: '3em', marginBottom: '20px', color: '#007AFF' }}>
        DuEasy
      </h1>
      <p style={{ fontSize: '1.5em', color: '#666', marginBottom: '40px' }}>
        AI-based invoice scanning app with automated reminders
      </p>
      <p style={{ fontSize: '1em', color: '#999' }}>
        Coming soon to the App Store
      </p>
      <div style={{ marginTop: '60px' }}>
        <a href="/privacy" style={{ color: '#007AFF', textDecoration: 'none', fontSize: '0.9em' }}>
          Privacy Policy
        </a>
      </div>
    </div>
  )
}
