class AuthMailer < ApplicationMailer
   default from: "noreply@stockflow-demo.id"

  def welcome_email(user)
    @user = user
    @frontend_login_url = "#{frontend_host}/login"
    @frontend_catalog_url = "#{frontend_host}/products"
    mail(
      to: user.email,
       subject: "Selamat datang di StockFlow Demo"
    )
  end

  def login_pin_email(user, pin)
    @user = user
    @pin = pin
    @frontend_login_url = "#{frontend_host}/login"
    mail(
      to: user.email,
       subject: "PIN Login Anda - StockFlow Demo"
    )
  end

  private

  def frontend_host
    ENV.fetch("FRONTEND_HOST", default_frontend_host)
  end

  def default_frontend_host
    if Rails.env.production?
      "https://app.rachmat.pro"
    elsif Rails.env.staging?
      "http://staging.rachmat.pro"
    else
      "http://localhost:5173"
    end
  end
end
