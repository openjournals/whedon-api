class Notifications < ApplicationMailer
  EDITOR_EMAILS = ["agahkarakuzu@gmail.com"]

  def welcome_email
    mail(to: EDITOR_EMAILS, subject: 'Well, just trying')
  end
end
