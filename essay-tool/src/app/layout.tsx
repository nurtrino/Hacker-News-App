import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Essay Tool",
  description: "Iterate on your college application essays with an AI council.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="min-h-screen antialiased">{children}</body>
    </html>
  );
}
