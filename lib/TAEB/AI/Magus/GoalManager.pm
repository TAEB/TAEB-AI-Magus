package TAEB::AI::Magus::GoalManager;
use Moose;

sub goals {
    return (
        'EarlyExperience',

        'EnterMines',
        'EnterMinetown',
        'MinetownAltar',
        'Izchak',
        'MinetownShops',

        'CoalignedAltar',
        'HolyWater',
        'LampWish',
        'Magicbane',

        'EnterSokoban',
        'MakeStash',
        'FinishSokoban',

        'UnicornHorn',
        'PoisonResistance',

        'QuestExperience',
        'FinishQuest',

        'GetCrowned',
        'KillShopkeepers',

        'Instrument',
        'EnterCastle',
        'FindTune',
        'CastleSmash',
        'CastleWand',

        'SpellExperience',
    );
}

sub current_goal {
}


1;

