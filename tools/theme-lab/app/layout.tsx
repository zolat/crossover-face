import type { Metadata } from "next";
import { headers } from "next/headers";
import "./globals.css";

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host = requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host") ?? "localhost";
  const protocol = requestHeaders.get("x-forwarded-proto") ?? "https";
  const image = `${protocol}://${host}/og.png`;
  return {
    title: "Colour Field Lab",
    description: "Prototype and compare colour palettes for Crossover Face.",
    openGraph: {
      title: "Colour Field Lab",
      description: "Prototype the field, not the hex.",
      images: [{ url: image, width: 1536, height: 1024, alt: "Colour Field Lab palette rings" }],
    },
    twitter: {
      card: "summary_large_image",
      title: "Colour Field Lab",
      description: "Prototype the field, not the hex.",
      images: [image],
    },
  };
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
