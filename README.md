# RoboNeuro API

A small service that provides the basic RoboNeuro API.
Used to help editors manage reviews for [The Journal of Open Source Software](http://joss.theoj.org).
You can see him in action in [this review issue](https://github.com/openjournals/joss-reviews/issues/78).

### Here are some things that RoboNeuro can do:

Here are some things you can ask me to do:

```
# List all of RoboNeuro's capabilities
@roboneuro commands

# Assign a GitHub user as the sole reviewer of this submission
@roboneuro assign @username as reviewer

# Add a GitHub user to the reviewers of this submission
@roboneuro add @username as reviewer

# Remove a GitHub user from the reviewers of this submission
@roboneuro remove @username as reviewer

# List of editor GitHub usernames
@roboneuro list editors

# List of reviewers together with programming language preferences and domain expertise
@roboneuro list reviewers

# Change editorial assignment
@roboneuro assign @username as editor

EDITOR-ONLY TASKS

# Remind an author or reviewer to return to a review after a
# certain period of time (supported units days and weeks)
@roboneuro remind @reviewer in 2 weeks

# Ask RoboNeuro to accept the paper
@roboneuro accept

```

## Development

Is it green? [![Build Status](https://travis-ci.org/openjournals/whedon-api.svg?branch=master)](https://travis-ci.org/openjournals/whedon-api)

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Deploying

To deploy a version of RoboNeuro on Heroku, an `app.json` template is provided:

[![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy?template=https://github.com/openjournals/whedon-api)
