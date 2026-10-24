#!/bin/sh
# Rewrite Cursor Agent author/committer to Abdullah Hanif
if [ "$GIT_AUTHOR_NAME" = "Cursor Agent" ] || [ "$GIT_AUTHOR_EMAIL" = "cursoragent@cursor.com" ]; then
  export GIT_AUTHOR_NAME="Abdullah Hanif"
  export GIT_AUTHOR_EMAIL="318923962+abdullahhanif-001@users.noreply.github.com"
fi
if [ "$GIT_COMMITTER_NAME" = "Cursor Agent" ] || [ "$GIT_COMMITTER_EMAIL" = "cursoragent@cursor.com" ]; then
  export GIT_COMMITTER_NAME="Abdullah Hanif"
  export GIT_COMMITTER_EMAIL="318923962+abdullahhanif-001@users.noreply.github.com"
fi
