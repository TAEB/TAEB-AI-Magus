package TAEB::AI::Magus::Goal::LampWish;
use Moose;
use TAEB::Util 'any';
extends 'TAEB::AI::Magus::Goal';

# XXX if we have an unknown lamp, either:
# try to bless and #rub it
# or price ID it

sub available_when { TAEB->has_item("magic lamp") }

sub prerequisite_goals { 'HolyWater' }

1;

