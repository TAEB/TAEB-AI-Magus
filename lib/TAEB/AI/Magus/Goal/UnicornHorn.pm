package TAEB::AI::Magus::Goal::UnicornHorn;
use Moose;
extends 'TAEB::AI::Magus::Goal';

sub met_when { TAEB->has_item('unicorn horn') }

1;

