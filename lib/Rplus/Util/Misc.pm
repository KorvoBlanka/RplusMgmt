package Rplus::Util::Misc;


sub generate_code {
    my @chars = ("A".."Z", "a".."z", "0".."9");
    my $reg_code;
    $reg_code .= $chars[rand @chars] for 1..20;

    return $reg_code;
}

1;
