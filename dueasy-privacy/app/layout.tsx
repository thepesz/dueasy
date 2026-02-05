export const metadata = {
  title: 'Privacy Policy - DuEasy',
  description: 'DuEasy Privacy Policy - AI-based invoice scanning app'
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body style={{
        fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
        lineHeight: '1.6',
        maxWidth: '800px',
        margin: '0 auto',
        padding: '20px',
        color: '#333'
      }}>
        {children}
      </body>
    </html>
  )
}
