# Contributing

This repository collects R-Ladies blogs, this is inclusive of those who identify as a minority gender (including but not limited to cis/trans women, trans men, non-binary, genderqueer, & agender).

All the blogs are listed in the [blogs](blogs/) folder, where each blog is in its own json-file. These files are used to render a table on the upcoming revamped R-Ladies website. We'd love to have contributions to this list! Follow the below instructions to add to the list.

## Adding a new entry

Depending on how you are most comfortable working, there are several ways of adding new entries. Here we will focus on adding new entries directly through GitHub, but you could also work on a local copy (branch) or fork and add new entries that way too.

### Copy content from an existing entry

Start by opening an existing entry and copy its content. This will give you a clear starting point for the new entry.

### Create a new file

In GitHub choose to create a new file (you could also prepare the file in your own text editor and upload if you like).

![Create a new file](images/contrib_newfile.png)

#### File name

The name of the file should be the site url (without `www` or `http(s)://` . This way we can ensure each file has a unique name and that duplication does not happen.

#### File content

Paste the content from the existing entry into the file, and edit the content.

There are several adaptations to an entry you can make that are not highlighted in every entry.

##### Authors

The entry may have several authors. This is for blogs where maybe there are several blogging together. If it is a blog that mainly has guest bloggers, its better to list the editors/maintainers of the blog and add "guest bloggers" as authors also.

Adding several authors means duplicating the content between the curlies `{}` in the author section, and adding a comma between each one.

``` {.json}
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
    "name": "Guest bloggers",
    "social_media": [{}]
  }
]
```

##### Icons

The `social_media` section supports many different key-value pairs. For rendering on the website, only the three first social media items for each author will be rendered.

``` {.json}
"twitter": "username"
"github": ""username
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

##### Language
The language field should be populated with the [ISO 639-1 Language Codes](https://www.w3schools.com/tags/ref_language_codes.asp) of the site content.
Please be thorough when entering this information.

### Commit and PR the file

At the bottom of the page on GitHub, add a commit message is the box. Choose to create a branch of your changes, and press `Propose changes`. 

![Propose changes](images/contrib_patch.png)

You will immediately be sent to the 'Pull requests' page, to create a PR to the master branch. 
Click the `Create pull request` button.
Once this is done, a new page will open and some automated checks of your submitted entries start. 
From the right-hand side-panel, click on "reviewers" and ask for @Athanasiamo as a reviewer.

If anything needs fixing you will be notified and given instructions on how to do that.

Once all checks pass and the entries have been reviewed, they will be merged to the master branch.
