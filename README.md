# Whedon API

A small service that provides the basic Whedon API. Used to help editors manage reviews for [The Journal of Open Source Software](http://joss.theoj.org). You can see him in action in [this review issue](https://github.com/openjournals/joss-reviews/issues/78).

### Here are some things that Whedon can do:

```
# List all of Whedon's capabilities
@whedon commands

# Assign a GitHub user as the sole reviewer of this submission
@whedon assign @username as reviewer

# Add a GitHub user to the reviewers of this submission
@whedon add @username as reviewer

# Remove a GitHub user from the reviewers of this submission
@whedon remove @username as reviewer

# List of editor GitHub usernames
@whedon list editors

# List of reviewers together with programming language preferences and domain expertise
@whedon list reviewers

# Change editorial assignment
@whedon assign @username as editor

# Set the software archive DOI at the top of the issue e.g.
@whedon set 10.0000/zenodo.00000 as archive

# Open the review issue
@whedon start review

🚧 🚧 🚧 Experimental Whedon features 🚧 🚧 🚧

# Compile the paper
@whedon generate pdf

```
