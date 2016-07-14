package Rplus::Util::Email;

use Rplus::Modern;

use MIME::Lite;
use IPC::Open2;
use JSON;
use Net::SMTP::SSL;

sub send {
    my ($self, $email, $message_text, $config) = @_;

    $self->app->log->debug(sprintf("Sending email: (%s) %s => %s", -1, $email, $message_text));
    my $s = send_email($email, 'Подобрана недвижимость', $message_text, $config);

    return 'success' if $s;
    return 'fail';
}

sub send_email {
    my ($to, $subject, $message, $config) = @_;

    my $from = $config->{'email-user'};

    my $msg = MIME::Lite->new(
                   From     => $from,
                   To       => $to,
                   Subject  => $subject,
                   Data     => $message
                   );
    $msg->attr("content-type" => "text/html; charset=UTF-8");
    #$msg->send('smtp', 'smtp.yandex.ru', AuthUser=>'info@rplusmgmt.com', AuthPass=>'ckj;ysqgfhjkm', Port => 587);

    my $port = 465;
    if ($config->{'email-port'} =~ /^(\d+)$/) {
      $port = $1;
    }

    my $smtp = Net::SMTP::SSL->new($config->{'email-smtp'}, Port => $port);
    if ($smtp) {
        $smtp->auth($config->{'email-user'}, $config->{'email-password'}); # or die "Can't authenticate:".$smtp->message();
        $smtp->mail($config->{'email-user'}); # or die "Error:".$smtp->message();
        $smtp->to($to); # or die "Error:".$smtp->message();
        $smtp->data(); # or die "Error:".$smtp->message();
        $smtp->datasend($msg->as_string); # or die "Error:".$smtp->message();
        $smtp->dataend(); # or die "Error:".$smtp->message();
        $smtp->quit(); # or die "Error:".$smtp->message();

        return 1;
    }

    return 0;
}

1;
