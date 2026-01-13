 # About

This repository collects R-Ladies community resources: content (one JSON per blog/channel) and R packages (one JSON per package). 
Contributions are welcome from anyone who identifies with the R-Ladies community.

# Contributing checklist

- [ ] The entry is added to the correct folder:
  - content metadata → `data/content/`
  - package metadata → `data/packages/`
- [ ] The entry filename ends with `.json`
- Content JSONs
  - [ ] Must include (minimum): `title`, `url` (rss feed url), `type` ("blog"), `authors`, `language` (see `scripts/json_schema/content.json` for full schema)
  - [ ] Name the file using the content's host (e.g. `your-blog-url.com.json`)
- Package JSONs 
  - [ ] Must include (minimum): `name`, `maintainers` (see `scripts/json_schema/packages.json` for full schema)
  - [ ] Name the file using the package name (e.g. `meetupr.json`)

# Contributing details

All blog metadata files live in `data/content/` and package metadata files live in `data/packages/`. 
Each entry is a single JSON file which is used to render pages and to generate aggregated JSONs in `data/website/`.

If you are not comfortable editing JSON directly, open an issue using the repository issue template and provide the details and we can help create the file for you.

There are two main ways to add an entry:

- Use the GitHub UI to create a new file in the appropriate folder (links below).
- Fork or branch locally, add the JSON file, and create a pull request.


## Create a new content file

Create a new file in `data/content/` (for example `data/content/your-blog-url.com.json`). You can use this link which pre-populates a template in a new file:

[data/content/your-url.com.json](https://github.com/rladies/awesome-rladies-blogs/new/main/?filename=data/content/your-url.com.json&value=%7B%0A%20%20%22title%22%3A%20%22Your%20title%22%2C%20%2F%2Frequired%0A%20%20%22subtitle%22%3A%20%22subtitle%20or%20tagline%22%2C%20%2F%2Foptional%0A%20%20%22type%22%3A%20%22blog%22%2C%20%2F%2Frequired%0A%20%20%22url%22%3A%20%22https%3A%2F%2Fyour_blog.com%22%2C%20%2F%2Frequired%0A%20%20%22photo_url%22%3A%20%22https%3A%2F%2Fyour_blog.com%2Fyour_photo.png%22%2C%20%2F%2Frequired%0A%20%20%22description%22%3A%20%22Short%20description%20of%20what%20you%20blog%20about%22%2C%0A%20%20%22language%22%3A%20%22en%22%2C%20%2F%2Frequired%0A%20%20%22rss_feed%22%3A%20%22%5Burl%5D%2Ffile.xml%22%2C%20%2F%2Frequired%0A%20%20%22authors%22%3A%20%5B%20%2F%2Frequired%0A%20%20%20%20%7B%0A%20%20%20%20%20%20%22name%22%3A%20%22Your%20Name%22%2C%20%2F%2Frequired%0A%20%20%20%20%20%20%22social_media%22%3A%20%5B%7B%0A%20%20%20%20%20%20%20%20%20%22twitter%22%3A%20%22username%22%2C%0A%20%20%20%20%20%20%20%20%20%22mastodon%22%3A%20%22%40username%40server.org%22%2C%0A%20%20%20%20%20%20%20%20%20%22bluesky%22%3A%20%22username.domain%22%2C%0A%20%20%20%20%20%20%20%20%20%22github%22%3A%20%22username%22%2C%0A%20%20%20%20%20%20%20%20%20%22instagram%22%3A%20%22username%22%2C%0A%20%20%20%20%20%20%20%20%20%22youtube%22%3A%20%22username%2Fend-url%22%2C%0A%20%20%20%20%20%20%20%20%20%22tiktok%22%3A%20%22username%22%2C%0A%20%20%20%20%20%20%20%20%20%22periscope%22%3A%20%22username%22%2C%0A%20%20%20%20%20%20%20%20%20%22researchgate%22%3A%20%22username%22%2C%0A%20%20%20%20%20%20%20%20%20%22website%22%3A%20%22url%22%2C%0A%20%20%20%20%20%20%20%20%20%22linkedin%22%3A%20%22username%22%2C%0A%20%20%20%20%20%20%20%20%20%22facebook%22%3A%20%22username%22%2C%0A%20%20%20%20%20%20%20%20%20%22orcid%22%3A%20%22member%20number%22%2C%0A%20%20%20%20%20%20%20%20%20%22meetup%22%3A%20%22end-url%22%0A%20%20%20%20%20%20%7D%5D%0A%20%20%20%20%7D%0A%20%20%5D%0A%7D).


**Template notes:**
- Follow the schema in `scripts/json_schema/content.json`. Required fields include `title`, `url`, `type`, `authors`, and `language`.
- Provide a `rss_feed` URL if you have a content-specific RSS (recommended for R-category posts).
- `photo_url` should be a publicly accessible image used as a thumbnail.


## Create a new package file

Create a new file in `data/packages/` (for example `data/packages/meetupr.json`). 
You can use this link which pre-populates a template in a new file:

[data/packages/meetupr.json](https://github.com/rladies/awesome-rladies-blogs/new/main/?filename=data/packages/your-package-name.json&value=%7B%0A%20%20%22name%22%3A%20%22Your%20title%22%2C%20%2F%2Frequired%0A%20%20%22description%22%3A%20%22Short%20description%20of%20what%20you%20blog%20about%22%2C%0A%20%20%22logo_url%22%3A%20%22https%3A%2F%2Fgithub.com%2Fusername%2Fpackage%2Fman%2Flogo.png%22%0A%20%20%22repo_url%22%3A%20%22https%3A%2F%2Fgithub.com%2Fusername%2Fpackage%22%2C%0A%20%20%22pkdown_url%3A%20%22https%3A%2F%2Fpkgdown.site%22%2C%0A%20%20%22maintainers%22%3A%20%5B%20%2F%2Frequired%0A%20%20%20%20%7B%0A%20%20%20%20%20%20%22name%22%3A%20%22Your%20Name%22%2C%20%2F%2Frequired%0A%20%20%20%20%20%20%22social_media%22%3A%20%5B%7B%0A%20%20%20%20%20%20%20%20%20%22twitter%22%3A%20%22username%22%2C%0A%20%20%20%20%20%20%20%20%20%22mastodon%22%3A%20%22%40username%40server.org%22%2C%0A%20%20%20%20%20%20%20%20%20%22bluesky%22%3A%20%22username.domain%22%2C%0A%20%20%20%20%20%20%20%20%20%22github%22%3A%20%22username%22%2C%0A%20%20%20%20%20%20%20%20%20%22instagram%22%3A%20%22username%22%2C%0A%20%20%20%20%20%20%20%20%20%22youtube%22%3A%20%22username%2Fend-url%22%2C%0A%20%20%20%20%20%20%20%20%20%22tiktok%22%3A%20%22username%22%2C%0A%20%20%20%20%20%20%20%20%20%22periscope%22%3A%20%22username%22%2C%0A%20%20%20%20%20%20%20%20%20%22researchgate%22%3A%20%22username%22%2C%0A%20%20%20%20%20%20%20%20%20%22website%22%3A%20%22url%22%2C%0A%20%20%20%20%20%20%20%20%20%22linkedin%22%3A%20%22username%22%2C%0A%20%20%20%20%20%20%20%20%20%22facebook%22%3A%20%22username%22%2C%0A%20%20%20%20%20%20%20%20%20%22orcid%22%3A%20%22member%20number%22%2C%0A%20%20%20%20%20%20%20%20%20%22meetup%22%3A%20%22end-url%22%0A%20%20%20%20%20%20%7D%5D%0A%20%20%20%20%7D%0A%20%20%5D%0A%7D)

**Template notes:**
- Follow the schema in `scripts/json_schema/packages.json`. Required fields include `name` and `maintainers`.
- Recommended fields: `repo_url`, `pkdown_url` (pkgdown or pkgdown-like site), `description`, `language`.


### File name conventions

- For blog entries (in `data/content/`) use the site host as the filename (e.g. `your-blog.com.json`, omit `www` and `http(s)://`).
- For package entries (in `data/packages/`) use the package or repository name (e.g. `meetupr.json`).


### Authors and social media

The `authors` array for blog entries accepts objects with `name` and an optional `social_media` array/object. For packages, the `maintainers` array accepts objects with `name` and `social_media`.

Only the first three social media items are rendered in the site UI; include handles for the services you want shown (twitter, github, mastodon, etc.).


### Validation and aggregation

- JSON schema files are available in `scripts/json_schema/` (`content.json` and `packages.json`). Use them to validate your JSON before submitting.
- Aggregated outputs (`data/website/awesome_blogs.json` and `data/website/awesome_packages.json`) are produced by `scripts/generate_website_jsons.R`.

If you'd like, you can run the validation locally; I can add a small script (`scripts/validate_package_jsons.R`) to do this automatically.

## Commit and PR the file

At the bottom of the GitHub file editor page, add a commit message and create a PR to `main`.

Once the PR is opened automated checks may run and we will review and request changes as needed. In the PR comments, please @rladies/website for review.

After checks pass and the entries are reviewed they will be merged into `main`.
