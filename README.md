# compareme

Answer questions about yourself, then step into a crowd and see where you blend in and where you stand apart.

**Live site:** https://robbiestells.github.io/compareme/

## What it does

- **You**: demographics (age, gender, region, household) plus questions on money, work, lifestyle and fun. Answers stay on your device until you sign in and save.
- **Crowd**: an animated crowd of figures that sorts itself by each question. Number questions become line-ups along a scale, choice questions split into groups, and **Most like me** places people closer the more alike your answers are. Zoom from the whole crowd down to you: a spotlight closes in and the captions switch from the big picture to your nearest neighbors. **Where I stand out** tours your most unusual answers.
- **Matches**: your 10 closest matches, what you have in common and where you differ.
- **Share**: a 1080×1350 card with your top stat drawn as a crowd of 100. On phones it opens the share sheet.
- **Ideas**: suggest and vote on new questions.
- **Admin** (admins only): review every suggestion, tidy the wording, and approve it into the survey, dismiss it, or restore it.

Until at least 3 real people have answered, the crowd is filled with 320 clearly labeled sample people so there's something to explore.

## Privacy

- You sign in with an email link. Your email is never shown or stored with your answers.
- The crowd is read through `cm_get_crowd()`, which returns only demographics and answers, never user ids.
- Results only appear when at least 3 people match the current filters.
- **Remove my answers** deletes your row.

## Where data lives

Everything is in a Supabase database (tables prefixed `cm_`), protected by row-level security:

| Table | What | Who can read | Who can write |
|---|---|---|---|
| `cm_responses` | one row of answers per person | only that person (others see it anonymously via `cm_get_crowd`) | only that person |
| `cm_suggestions` | suggested questions | via `cm_get_suggestions` (vote counts, no authors) | authors add/delete their own; admins change status |
| `cm_votes` | one vote per person per suggestion | only the voter | only the voter |
| `cm_questions` | community questions in the survey | everyone | admins |
| `cm_admins`, `cm_admin_emails` | who's an admin (by user id or email; robbiestells@gmail.com is seeded) | nobody via the API | SQL editor only |

Without `config.js` filled in, the site runs with the sample crowd and saving turned off.

## Setup (one time)

1. In your Supabase project, open **SQL Editor**, paste [`supabase/setup.sql`](supabase/setup.sql) and run it.
2. Open **Authentication → URL Configuration** and add `https://robbiestells.github.io/compareme/` under **Redirect URLs**.
3. Put the project's **Project URL** and **publishable / anon** key in [`config.js`](config.js). Both are safe to publish. Never put the secret or service_role key here.
4. In the GitHub repo, open **Settings → Pages**, choose **Deploy from a branch**, branch `main`, folder `/ (root)`.
5. Sign in on the live site with robbiestells@gmail.com. That email is an admin out of the box, so an **Admin** tab appears for reviewing, editing, approving, dismissing and restoring suggested questions. To add another admin, add their email to `cm_admin_emails` (see the bottom of `setup.sql`).

If suggestions say the database isn't set up, step 1 hasn't been run yet in this Supabase project.
