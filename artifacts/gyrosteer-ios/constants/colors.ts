/**
 * Semantic design tokens for the mobile app.
 *
 * These tokens mirror the naming conventions used in web artifacts (index.css)
 * so that multi-artifact projects share a cohesive visual identity.
 *
 * Replace the placeholder values below with values that match the project's
 * brand. If a sibling web artifact exists, read its index.css and convert the
 * HSL values to hex so both artifacts use the same palette.
 *
 * To add dark mode, add a `dark` key with the same token names.
 * The useColors() hook will automatically pick it up.
 */

const colors = {
  light: {
    // Legacy aliases (kept for backward compatibility)
    text: '#EEF4F6',
    tint: '#46E6D0',

    // Core surfaces
    background: '#090E13',
    foreground: '#EEF4F6',

    // Cards / elevated surfaces
    card: '#121A22',
    cardForeground: '#EEF4F6',

    // Primary action color (buttons, links, active states)
    primary: '#46E6D0',
    primaryForeground: '#06110F',

    // Secondary / less-emphasis interactive surfaces
    secondary: '#1B2630',
    secondaryForeground: '#E5EEF2',

    // Muted / subdued elements (dividers, timestamps, placeholders)
    muted: '#17212A',
    mutedForeground: '#82929C',

    // Accent highlights (badges, selected items, focus rings)
    accent: '#FF654A',
    accentForeground: '#FFFFFF',

    // Destructive actions (delete, error states)
    destructive: '#FF5D68',
    destructiveForeground: '#FFFFFF',

    // Borders and input outlines
    border: '#26343E',
    input: '#2A3944',
    wheelRim: '#27343E',
    wheelFace: '#0D141A',
    wheelSpoke: '#202B34',
    wheelHub: '#101820',
    brakeFill: '#FFE4E7',
    brakeBorder: '#55333A',
    throttleBorder: '#285A54',
  },

  dark: {
    text: '#EEF4F6',
    tint: '#46E6D0',
    background: '#090E13',
    foreground: '#EEF4F6',
    card: '#121A22',
    cardForeground: '#EEF4F6',
    primary: '#46E6D0',
    primaryForeground: '#06110F',
    secondary: '#1B2630',
    secondaryForeground: '#E5EEF2',
    muted: '#17212A',
    mutedForeground: '#82929C',
    accent: '#FF654A',
    accentForeground: '#FFFFFF',
    destructive: '#FF5D68',
    destructiveForeground: '#FFFFFF',
    border: '#26343E',
    input: '#2A3944',
    wheelRim: '#27343E',
    wheelFace: '#0D141A',
    wheelSpoke: '#202B34',
    wheelHub: '#101820',
    brakeFill: '#FFE4E7',
    brakeBorder: '#55333A',
    throttleBorder: '#285A54',
  },

  // Border radius (in px). Sync from the sibling web artifact's --radius
  // CSS variable. This value applies to cards, buttons, inputs, and modals.
  radius: 16,
};

export default colors;
