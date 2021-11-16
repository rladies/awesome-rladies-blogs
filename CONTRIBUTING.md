# About 

This repository collects R-Ladies blogs, this is inclusive of those who identify as a minority gender (including but not limited to cis/trans women, trans men, non-binary, genderqueer, & agender). We'd love to have contributions to this list! If you identify with R-Ladies and have a blog, please add yourself.

# Contributing checklist

 - [ ] The entry is added to [blogs/](blogs/) folder
 - [ ] The entry filename ends with `.json`
 - [ ] The json contains at minimum: 
     - [ ] title (blog title)
     - [ ] type ("blog")
     - [ ] url (blog url)
     - [ ] photo_url (logo or profile)
     - [ ] language (one of [ISO 639-1 Language Codes](https://www.w3schools.com/tags/ref_language_codes.asp))
     - [ ] authors (list of authors)

# Contributing details

All the blogs are listed in the [blogs](blogs/) folder, where each blog is in its own json-file. These files are used to render a table on the upcoming revamped R-Ladies website. Follow the below instructions to add to the list. If you have any trouble, please create an issue for us to help.

Depending on how you are most comfortable working, there are several ways of adding new entries. 

If you are not familiar with JSON you can [open an issue](https://github.com/rladies/awesome-rladies-blogs/issues/new/choose) with your blog info, which uses a GitHub Form, and we'd create the JSON for you!

Now we will focus on adding new entries directly through GitHub, but you could also work on a local copy (branch) or fork and add new entries that way too.

## Copy json format 

Copy the below template so you can paste it into a new file later.

```json
{
  "title": "Your title", //required
  "subtitle": "subtitle or tagline", //optional
  "type": "blog", //required
  "url": "https://your_blog.com", //required
  "photo_url": "https://your_blog.com/your_photo.png", //required
  "description": "Short description of what you blog about", //optional
  "language": "en (required)", //required
  "authors": [ //required
    {
      "name": "Your Name", //required
      "social_media": [{
        "twitter": "twitter-handle",
        "github": "github-handle"
      }]
    }
  ]
}
```

## Create a new file

In GitHub, navigate to the [blogs/](blogs/) folder, and choose to create a new file (you could also prepare the file in your own text editor and upload if you like).

![Create a new file](images/contrib_newfile.png)


### File name

The name of the file should be the site url (without `www` or `http(s)://` . This way we can ensure each file has a unique name and that duplication does not happen.

### File content

There are several adaptations to an entry you can make that are not highlighted in every entry.
If you copied the json template from above, remove all mentions of `\\required` or `\\optional`, these are just for making it clear which information you _must_ provide and which are optional.
Any optional field you don't want to add, you may delete entirely.
For instance, if you don't have a subtitle or tagline for your blog, remove the entire line of `"subtite": "subtitle or tagline"` rather than leaving it empty with `"subtite": ""`

#### Authors

The entry may have several authors. This is for blogs where maybe there are several blogging together. If it is a blog that mainly has guest bloggers, its better to list the editors/maintainers of the blog and add "guest bloggers" as authors also.

Adding several authors means duplicating the content between the curlies `{}` in the author section, and adding a comma between each one.

```json
"authors": [
  {
    "name": "Athanasia Mo  Mowinckel",
    "social_media": [{
      "twitter": "DrMowinckels",
      "github": "Athanasiamo"
    }]
  },
  {
    "name": "Mary Johnson",
    "social_media": [{
      "linkedin": "maryj",
      "youtube": "maryj"
    }]
  },
  {
    "name": "Guest bloggers"
  }
]
```

#### Icons

The `social_media` section supports many different key-value pairs. 
For rendering on the website, only the three first social media items for each author will be rendered.

```json
"twitter": "username"
"github": "username"
"instagram": "username"
"youtube": "username/end-url"
"tiktok": "username"
"periscope": "username"
"researchgate": "username"
"website": "url"
"linkedin": "username"
"facebook": "username"
"orcid": "member number"
"meetup": "end-url"
```

#### Language
The language field should be populated with the [ISO 639-1 Language Codes](https://www.w3schools.com/tags/ref_language_codes.asp) of the site content.
Please be thorough when entering this information.

## Commit and PR the file

At the bottom of the page on GitHub, add a commit message in the box. Choose to create a branch of your changes, and press `Propose changes`. 

![Propose changes](images/contrib_patch.png)

You will immediately be sent to the 'Pull requests' page, to create a PR to the master branch. 
Click the `Create pull request` button.
Once this is done, a new page will open and some automated checks of your submitted entries start. 
In the comment section, make sure to @Athanasiamo so she can take a look.

If anything needs fixing you will be notified and given instructions on how to do that.

Once all checks pass and the entries have been reviewed, they will be merged to the master branch.
