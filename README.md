# compareme

Answer questions about yourself, then step into a crowd and see where you blend in and where you stand apart.

## Features

- **You**: demographics (age, gender, region, household) plus questions on money, work, lifestyle and fun.
- **Crowd**: an animated crowd of figures that sorts itself by each question. Number questions become line-ups, choice questions become groups, and "Most like me" places people by how similar their answers are. Zoom from the whole crowd down to you; a spotlight and live captions show where you fit and where you stand out. "Where I stand out" tours your most unusual answers.
- **Matches**: your 10 closest matches, what you have in common and where you differ (anonymous).
- **Share**: a 1080×1350 card for social media, with your top stat drawn as a crowd of 100.
- **Ideas**: suggest and vote on new questions; the owner can add winners to the survey.

## Running it

It's a single self-contained `index.html` with no build step.

Shared answers, suggestions and saving run on the Claude artifact runtime (`window.claude`). Opened anywhere else (for example GitHub Pages or a local file), the app runs in demo mode with a 320-person sample crowd and saving turned off. To run it standalone with real users, swap the `db`/`user` calls for a backend such as Firebase or Supabase.
