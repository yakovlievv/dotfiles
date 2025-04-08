return {
  'eandrju/cellular-automaton.nvim',
  keys = {
    {
      "<leader>cr",
      function()
        require("cellular-automaton").start_animation("make_it_rain")
      end,
      desc = "Start Cellular Automaton Rain"
    }
  }
}

